//! Local modpack filesystem operations and import/export flows.

use crate::{
    Result,
    events::BackendEvent,
    mc_mod::enrich_installed_mod,
    models::{
        InstalledMod, InstalledModpack, LocalModpack, ModLoader, ModSource, SyncInfo, modpack_path,
    },
    ports::{EventSink, SettingsStore},
};
use anyhow::anyhow;
use chrono::Utc;
use futures::StreamExt;
use std::{
    io::Write,
    path::{Path, PathBuf},
    sync::Arc,
};
use tokio::sync::Mutex;
use zip::write::{ExtendedFileOptions, FileOptions};

/// Discovers local modpacks under `<mcFolder>/modpacks`.
pub async fn get_modpacks(mc_folder: &Path, hide_free: bool) -> Result<Vec<LocalModpack>> {
    let mut modpacks = Vec::new();
    let modpacks_folder = mc_folder.join("modpacks");
    if !modpacks_folder.exists() {
        return Ok(modpacks);
    }
    let mods_folder = mc_folder.join("mods");

    for entry in std::fs::read_dir(modpacks_folder)? {
        let entry = entry?;
        let path = entry.path();

        // Skip non-directory entries before trying to read them as folders.
        // macOS drops `.DS_Store` files into directories, and calling
        // `read_dir` on a file errors out — which previously failed the whole
        // modpack listing on macOS.
        if !path.is_dir() {
            continue;
        }

        let file_amount = std::fs::read_dir(&path)?.count();

        let mut extra_files = 0;
        let modpack_config_v2 = path.join("modConfigV2.json");
        let modpack_config_v1 = path.join("modConfig.json");
        let modpack_sync = path.join("quadrantSync.json");
        let mut last_synced = 0_i64;
        let mut modpack_id = None;
        let name = path.file_name().unwrap().to_string_lossy().to_string();

        if hide_free && name == "free" {
            continue;
        }

        let is_applied = mods_folder
            .is_symlink()
            .then(|| mods_folder.read_link().ok())
            .flatten()
            .is_some_and(|mods_path| mods_path == path);

        let has_v2 = modpack_config_v2.exists();
        let has_v1 = modpack_config_v1.exists();

        if !has_v2 && !has_v1 {
            modpacks.push(LocalModpack {
                name,
                version: "-".to_string(),
                mods: Vec::new(),
                mod_loader: ModLoader::Unknown,
                is_applied,
                last_synced,
                modpack_id: None,
                unknown_mods: true,
            });
            continue;
        }

        if modpack_sync.exists() {
            extra_files += 1;
            let sync_info = std::fs::File::open(modpack_sync)?;
            let reader = std::io::BufReader::new(sync_info);
            let sync_info: SyncInfo = serde_json::from_reader(reader)?;
            last_synced = sync_info.last_synced * 1000;
            modpack_id = sync_info.modpack_id;
        }

        let config_path = if has_v2 { &modpack_config_v2 } else { &modpack_config_v1 };
        let config_file = std::fs::File::open(config_path)?;
        let reader = std::io::BufReader::new(config_file);
        let parsed: std::result::Result<InstalledModpack, serde_json::Error> =
            serde_json::from_reader(reader);
        if parsed.is_err() {
            modpacks.push(LocalModpack::from((
                InstalledModpack {
                    mod_config_version: String::new(),
                    quadrant_version: String::new(),
                    mod_loader: ModLoader::Unknown,
                    name,
                    version: "1.12.2".to_string(),
                    mods: Vec::new(),
                },
                is_applied,
                last_synced,
            )));
            continue;
        }

        let mut modpack = parsed?;
        modpack.name = name.clone();

        let mut needs_rewrite = false;

        if !has_v2 {
            modpack.mod_config_version = "2".to_string();
            modpack.quadrant_version = crate::models::quadrant_version();
            needs_rewrite = true;
        }

        for mod_ in &mut modpack.mods {
            if mod_.name.is_empty() && mod_.source != ModSource::Online {
                match enrich_installed_mod(mod_.clone()).await {
                    Ok(enriched) => {
                        *mod_ = enriched;
                        needs_rewrite = true;
                    }
                    Err(e) => {
                        log::warn!(
                            "Failed to enrich mod {} in modpack \"{}\": {}",
                            mod_.id,
                            name,
                            e
                        );
                    }
                }
            }
        }

        if needs_rewrite {
            match std::fs::write(
                &modpack_config_v2,
                serde_json::to_string_pretty(&modpack)?,
            ) {
                Ok(()) => {
                    if has_v1 && !has_v2 {
                        let _ = std::fs::remove_file(&modpack_config_v1);
                    }
                }
                Err(e) => {
                    log::error!(
                        "Failed to write modConfigV2.json for modpack \"{}\": {}",
                        name,
                        e
                    );
                }
            }
        }

        let v2_file_count = if modpack_config_v2.exists() { 1 } else { 0 };
        let v1_file_count = if modpack_config_v1.exists() { 1 } else { 0 };
        extra_files += v2_file_count + v1_file_count;

        let mut modpack = LocalModpack::from((modpack, is_applied, last_synced));
        modpack.modpack_id = modpack_id;
        let expected_files = modpack.mods.len() + extra_files;
        if expected_files < file_amount {
            modpack.unknown_mods = true;
        }
        modpacks.push(modpack);
    }

    Ok(modpacks)
}

/// Applies the named modpack by making `<mcFolder>/mods` point at it.
pub fn apply_modpack(mc_folder: &Path, name: &str) -> Result<()> {
    log::info!("Applying modpack \"{name}\"");
    let modpack_dir = modpack_path(mc_folder, name);
    let mods_path = mc_folder.join("mods");
    if !modpack_dir.exists() {
        return Err(anyhow!("Modpack does not exist"));
    }
    if !mods_path.is_symlink() && mods_path.exists() {
        std::fs::rename(
            &mods_path,
            mc_folder
                .join("modpacks")
                .join(format!("mods backup from {}", Utc::now().to_rfc2822())),
        )?;
    } else if mods_path.exists() {
        std::fs::remove_dir_all(&mods_path)?;
    }

    #[cfg(target_os = "windows")]
    {
        let sym_res = std::os::windows::fs::symlink_dir(modpack_dir, &mods_path);
        if sym_res.is_err() {
            std::fs::remove_dir_all(&mods_path)?;
            apply_modpack(mc_folder, name)?;
        }
    }

    #[cfg(any(target_os = "linux", target_os = "macos"))]
    {
        std::os::unix::fs::symlink(modpack_dir, mods_path)?;
    }
    Ok(())
}

/// Creates a new modpack folder and manifest.
pub fn create_modpack(
    mc_folder: &Path,
    existing_modpacks: &[LocalModpack],
    name: &str,
    version: &str,
    mod_loader: ModLoader,
) -> Result<()> {
    log::info!("Creating modpack \"{name}\" (version={version}, mod_loader={mod_loader:?})");
    if existing_modpacks.iter().any(|modpack| modpack.name == name) {
        return Err(anyhow!("Modpack exists"));
    }
    let modpack_folder = modpack_path(mc_folder, name);
    std::fs::create_dir_all(&modpack_folder)?;
    let modpack = InstalledModpack {
        mod_config_version: "2".to_string(),
        quadrant_version: crate::models::quadrant_version(),
        name: name.to_string(),
        version: version.to_string(),
        mod_loader,
        mods: Vec::new(),
    };
    std::fs::write(
        modpack_folder.join("modConfigV2.json"),
        serde_json::to_string_pretty(&modpack)?,
    )?;
    Ok(())
}

/// Updates an existing modpack manifest and optionally renames the modpack.
pub fn update_modpack(
    mc_folder: &Path,
    existing_modpacks: &[LocalModpack],
    modpack_source: &str,
    name: Option<String>,
    version: Option<String>,
    mod_loader: Option<ModLoader>,
) -> Result<LocalModpack> {
    log::info!(
        "Updating modpack \"{modpack_source}\" (name={name:?}, version={version:?}, mod_loader={mod_loader:?})"
    );
    let mut modpack = existing_modpacks
        .iter()
        .find(|modpack| modpack.name == modpack_source)
        .cloned()
        .ok_or_else(|| anyhow!("No modpack found"))?;
    let modpack_folder = modpack_path(mc_folder, modpack_source);
    let original_name = modpack.name.clone();

    if let Some(name) = name.clone() {
        modpack.name = name;
    }
    if let Some(version) = version {
        modpack.version = version;
    }
    if let Some(mod_loader) = mod_loader {
        modpack.mod_loader = mod_loader;
    }

    std::fs::write(
        modpack_folder.join("modConfigV2.json"),
        serde_json::to_string_pretty(&InstalledModpack::from(modpack.clone()))?,
    )?;

    if modpack.name != original_name {
        std::fs::rename(&modpack_folder, modpack_path(mc_folder, &modpack.name))?;
    }

    Ok(modpack)
}

/// Deletes a modpack and removes the active `mods` link if needed.
pub fn delete_modpack(
    mc_folder: &Path,
    existing_modpacks: &[LocalModpack],
    name: &str,
) -> Result<()> {
    log::info!("Deleting modpack \"{name}\"");
    let is_applied = existing_modpacks
        .iter()
        .find(|modpack| modpack.name == name)
        .map(|modpack| modpack.is_applied)
        .ok_or_else(|| anyhow!("Modpack doesn't exist"))?;

    let mods_folder = mc_folder.join("mods");
    if is_applied && mods_folder.exists() {
        std::fs::remove_dir_all(mods_folder)?;
    }

    std::fs::remove_dir_all(modpack_path(mc_folder, name))?;
    Ok(())
}

/// Registers a mod entry inside the target modpack manifest.
pub async fn register_mod(
    mc_folder: &Path,
    existing_modpacks: &[LocalModpack],
    mut mod_: InstalledMod,
    modpack_name: &str,
) -> Result<()> {
    log::info!("Registering mod {} in modpack \"{modpack_name}\"", mod_.id);
    let mut modpack = existing_modpacks
        .iter()
        .find(|modpack| modpack.name == modpack_name)
        .cloned()
        .ok_or_else(|| anyhow!("Modpack doesn't exist"))?;

    if modpack.mods.iter().any(|existing| existing.id == mod_.id) {
        return Err(anyhow!("Mod already registered"));
    }

    if mod_.name.is_empty() && mod_.source != ModSource::Online {
        match enrich_installed_mod(mod_.clone()).await {
            Ok(enriched) => mod_ = enriched,
            Err(e) => log::warn!(
                "Failed to enrich mod {} in modpack \"{}\": {}",
                mod_.id,
                modpack_name,
                e
            ),
        }
    }

    modpack.mods.push(mod_);

    std::fs::write(
        modpack_path(mc_folder, modpack_name).join("modConfigV2.json"),
        serde_json::to_string_pretty(&InstalledModpack::from(modpack))?,
    )?;
    Ok(())
}

/// Removes a mod entry and its downloaded file from a modpack.
pub fn delete_mod(
    mc_folder: &Path,
    existing_modpacks: &[LocalModpack],
    modpack_name: &str,
    mod_id: &str,
) -> Result<LocalModpack> {
    log::info!("Deleting mod {mod_id} from modpack \"{modpack_name}\"");
    let mut modpack = existing_modpacks
        .iter()
        .find(|modpack| modpack.name == modpack_name)
        .cloned()
        .ok_or_else(|| anyhow!("No modpack found"))?;

    let modpack_folder = modpack_path(mc_folder, modpack_name);
    let to_delete_ids: Vec<_> = modpack
        .mods
        .iter()
        .filter(|mod_| mod_.id == mod_id)
        .map(|mod_| mod_.id.clone())
        .collect();
    if to_delete_ids.is_empty() {
        return Err(anyhow!("No mods found"));
    }

    let to_delete_paths: Vec<_> = modpack
        .mods
        .iter()
        .filter(|mod_| mod_.id == mod_id)
        .map(|mod_| {
            let url = urlencoding::decode(mod_.download_url.split('/').last().unwrap_or_default())
                .unwrap_or_default()
                .into_owned();
            modpack_folder.join(url)
        })
        .collect();
    modpack
        .mods
        .retain(|mod_| !to_delete_ids.contains(&mod_.id));

    for file in to_delete_paths {
        std::fs::remove_file(file)?;
    }

    std::fs::write(
        modpack_folder.join("modConfigV2.json"),
        serde_json::to_string_pretty(&InstalledModpack::from(modpack.clone()))?,
    )?;
    Ok(modpack)
}

/// Persists the sync metadata for a modpack.
pub fn set_modpack_sync_date(
    mc_folder: &Path,
    time: u64,
    modpack: &str,
    modpack_id: Option<&str>,
) -> Result<()> {
    std::fs::write(
        modpack_path(mc_folder, modpack).join("quadrantSync.json"),
        serde_json::to_string_pretty(&SyncInfo {
            last_synced: time as i64,
            modpack_id: modpack_id.map(ToOwned::to_owned),
        })?,
    )?;
    Ok(())
}

/// Downloads the files declared by a modpack manifest into its local folder.
///
/// Progress is emitted through [`BackendEvent::ModpackDownloadProgress`].
pub async fn install_modpack(
    mc_folder: &Path,
    mut mod_config: InstalledModpack,
    settings: &impl SettingsStore,
    event_sink: &impl EventSink,
) -> Result<()> {
    log::info!(
        "Installing modpack \"{}\" ({} mod(s))",
        mod_config.name,
        mod_config.mods.len()
    );
    let modpack_folder = modpack_path(mc_folder, &mod_config.name);
    if !modpack_folder.exists() {
        std::fs::create_dir_all(&modpack_folder)?;
    }

    mod_config.mod_config_version = "2".to_string();
    mod_config.quadrant_version = crate::models::quadrant_version();

    for mod_ in &mut mod_config.mods {
        if mod_.name.is_empty() && mod_.source != ModSource::Online {
            match enrich_installed_mod(mod_.clone()).await {
                Ok(enriched) => *mod_ = enriched,
                Err(e) => log::warn!(
                    "Failed to enrich mod {} in modpack \"{}\": {}",
                    mod_.id,
                    mod_config.name,
                    e
                ),
            }
        }
    }

    std::fs::write(
        modpack_folder.join("modConfigV2.json"),
        serde_json::to_string_pretty(&mod_config)?,
    )?;

    let mods = mod_config.mods.clone();
    let existing_files = std::fs::read_dir(&modpack_folder)?;
    let mut expected_file_names = Vec::new();
    for mod_ in &mods {
        expected_file_names.push(
            urlencoding::decode(mod_.download_url.split('/').last().unwrap_or_default())?
                .into_owned(),
        );
    }

    for file in existing_files {
        let file = file?;
        let file_name = file.file_name().to_string_lossy().to_string();
        if file_name != "modConfigV2.json" && !expected_file_names.contains(&file_name) {
            std::fs::remove_file(file.path())?;
        }
    }

    let total_mods = mods.len();
    let downloaded_mods = Arc::new(Mutex::new(0_usize));
    let mut downloads = Vec::new();
    for mod_ in mods {
        let file_name =
            urlencoding::decode(mod_.download_url.split('/').last().unwrap_or_default())?
                .into_owned();
        let file_path = modpack_folder.join(file_name);
        if file_path.exists() {
            continue;
        }

        downloads.push(download_mod_concurrently(
            mod_,
            file_path,
            settings,
            event_sink,
            total_mods,
            downloaded_mods.clone(),
        ));
    }

    for result in futures::future::join_all(downloads).await {
        result?;
    }

    event_sink.publish(BackendEvent::ModpackDownloadProgress(1.0))?;
    log::info!("Modpack installation complete");
    Ok(())
}

/// Exports a modpack folder as a Quadrant zip archive at the provided path.
///
/// Progress is emitted through [`BackendEvent::QuadrantExportProgress`].
pub fn export_modpack_to(
    mc_folder: &Path,
    modpack: &str,
    destination: &Path,
    event_sink: &impl EventSink,
) -> Result<()> {
    log::info!(
        "Exporting modpack \"{modpack}\" to {}",
        destination.display()
    );
    let modpack_folder = modpack_path(mc_folder, modpack);
    let destination = std::fs::File::create(destination)?;
    let mut zip = zip::ZipWriter::new(destination);
    let options: FileOptions<ExtendedFileOptions> = FileOptions::default()
        .compression_method(zip::CompressionMethod::Bzip2)
        .unix_permissions(0o755)
        .compression_level(Some(9))
        .large_file(true);

    let total_files = std::fs::read_dir(&modpack_folder)?
        .filter_map(|entry| entry.ok())
        .count();
    let mut written_files = 0_usize;
    let mut zip_issues = false;

    for file in std::fs::read_dir(&modpack_folder)? {
        let file = file?;
        let contents = std::fs::read(file.path())?;
        let file_name = file.file_name().to_string_lossy().to_string();

        if zip.start_file(file_name.clone(), options.clone()).is_err() {
            zip_issues = true;
            continue;
        }
        if zip.write_all(&contents).is_err() {
            zip_issues = true;
            continue;
        }

        written_files += 1;
        event_sink.publish(BackendEvent::QuadrantExportProgress(
            written_files as f64 / total_files as f64,
        ))?;
    }

    if zip.finish().is_err() || zip_issues {
        return Err(anyhow!("Failed to finish zip"));
    }

    event_sink.publish(BackendEvent::QuadrantExportProgress(1.0))?;
    log::info!("Modpack export complete");
    Ok(())
}

async fn download_mod_concurrently(
    mod_: InstalledMod,
    file: PathBuf,
    settings: &impl SettingsStore,
    event_sink: &impl EventSink,
    total_mods: usize,
    downloaded_mods: Arc<Mutex<usize>>,
) -> Result<()> {
    let response = reqwest::get(&mod_.download_url).await?;
    let mut bytes = response.bytes_stream();
    let mut file = std::fs::File::create(file)?;
    while let Some(item) = bytes.next().await {
        file.write_all(&item?)?;
    }

    let current_key = match mod_.source {
        ModSource::CurseForge => Some("curseforgeUsage"),
        ModSource::Modrinth => Some("modrinthUsage"),
        ModSource::Online => None,
    };
    if let Some(current_key) = current_key {
        let current_value = settings.get_i64(current_key)?.unwrap_or_default();
        settings.set_i64(current_key, current_value + 1)?;
    }

    let mut downloaded = downloaded_mods.lock().await;
    *downloaded += 1;
    event_sink.publish(BackendEvent::ModpackDownloadProgress(
        *downloaded as f64 / total_mods as f64,
    ))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{config::ensure_default_app_config, ports::SettingsStore};
    use httpmock::prelude::*;
    use serde_json::Value;
    use std::{cell::RefCell, collections::HashMap, io::Read};
    use tempfile::tempdir;

    #[derive(Default)]
    struct MemoryStore {
        values: RefCell<HashMap<String, Value>>,
    }

    impl SettingsStore for MemoryStore {
        fn get_value(&self, key: &str) -> Result<Option<Value>> {
            Ok(self.values.borrow().get(key).cloned())
        }

        fn set_value(&self, key: &str, value: Value) -> Result<()> {
            self.values.borrow_mut().insert(key.to_string(), value);
            Ok(())
        }

        fn entries(&self) -> Result<Vec<(String, Value)>> {
            Ok(self
                .values
                .borrow()
                .iter()
                .map(|(key, value)| (key.clone(), value.clone()))
                .collect())
        }
    }

    #[derive(Default)]
    struct CollectingEvents {
        events: RefCell<Vec<BackendEvent>>,
    }

    impl EventSink for CollectingEvents {
        fn publish(&self, event: BackendEvent) -> Result<()> {
            self.events.borrow_mut().push(event);
            Ok(())
        }
    }

    fn setup_mc_folder() -> (tempfile::TempDir, PathBuf) {
        let dir = tempdir().unwrap();
        let mc_folder = dir.path().join(".minecraft");
        std::fs::create_dir_all(mc_folder.join("modpacks")).unwrap();
        (dir, mc_folder)
    }

    #[tokio::test]
    async fn create_update_register_delete_and_discover_modpacks() {
        let (_dir, mc_folder) = setup_mc_folder();
        let existing = get_modpacks(&mc_folder, false).await.unwrap();
        create_modpack(&mc_folder, &existing, "alpha", "1.20.1", ModLoader::Fabric).unwrap();

        let listed = get_modpacks(&mc_folder, false).await.unwrap();
        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].name, "alpha");

        register_mod(
            &mc_folder,
            &listed,
            InstalledMod::minimal(
                "mod-1".to_string(),
                ModSource::Modrinth,
                "https://example.invalid/mod.jar".to_string(),
            ),
            "alpha",
        )
        .await
        .unwrap();

        let listed = get_modpacks(&mc_folder, false).await.unwrap();
        assert_eq!(listed[0].mods.len(), 1);
        std::fs::write(modpack_path(&mc_folder, "alpha").join("mod.jar"), "jar").unwrap();

        let updated = update_modpack(
            &mc_folder,
            &listed,
            "alpha",
            Some("beta".to_string()),
            Some("1.21".to_string()),
            Some(ModLoader::NeoForge),
        )
        .unwrap();
        assert_eq!(updated.name, "beta");

        set_modpack_sync_date(&mc_folder, 42, "beta", Some("modpack-123")).unwrap();
        let listed = get_modpacks(&mc_folder, false).await.unwrap();
        assert_eq!(listed[0].last_synced, 42_000);
        assert_eq!(listed[0].modpack_id.as_deref(), Some("modpack-123"));

        delete_mod(&mc_folder, &listed, "beta", "mod-1").unwrap();
        let listed = get_modpacks(&mc_folder, false).await.unwrap();
        assert!(listed[0].mods.is_empty());

        delete_modpack(&mc_folder, &listed, "beta").unwrap();
        assert!(get_modpacks(&mc_folder, false).await.unwrap().is_empty());
    }

    #[tokio::test]
    async fn get_modpacks_reads_legacy_sync_metadata_without_modpack_id() {
        let (_dir, mc_folder) = setup_mc_folder();
        std::fs::create_dir_all(modpack_path(&mc_folder, "legacy")).unwrap();
        std::fs::write(
            modpack_path(&mc_folder, "legacy").join("modConfig.json"),
            serde_json::to_string_pretty(&InstalledModpack {
                mod_config_version: String::new(),
                quadrant_version: String::new(),
                name: "legacy".to_string(),
                version: "1.20.1".to_string(),
                mod_loader: ModLoader::Fabric,
                mods: Vec::new(),
            })
            .unwrap(),
        )
        .unwrap();
        std::fs::write(
            modpack_path(&mc_folder, "legacy").join("quadrantSync.json"),
            r#"{"last_synced":99}"#,
        )
        .unwrap();

        let listed = get_modpacks(&mc_folder, false).await.unwrap();
        assert_eq!(listed[0].last_synced, 99_000);
        assert_eq!(listed[0].modpack_id, None);
    }

    #[test]
    fn export_modpack_to_zip() {
        let (_dir, mc_folder) = setup_mc_folder();
        std::fs::create_dir_all(modpack_path(&mc_folder, "alpha")).unwrap();
        std::fs::write(
            modpack_path(&mc_folder, "alpha").join("modConfigV2.json"),
            "{}",
        )
        .unwrap();
        std::fs::write(modpack_path(&mc_folder, "alpha").join("sample.jar"), "jar").unwrap();

        let destination = mc_folder.join("alpha.quadrantExport.zip");
        export_modpack_to(
            &mc_folder,
            "alpha",
            &destination,
            &CollectingEvents::default(),
        )
        .unwrap();

        let file = std::fs::File::open(destination).unwrap();
        let mut archive = zip::ZipArchive::new(file).unwrap();
        let mut file = archive.by_name("sample.jar").unwrap();
        let mut contents = String::new();
        file.read_to_string(&mut contents).unwrap();
        assert_eq!(contents, "jar");
    }

    #[tokio::test]
    async fn install_modpack_downloads_files_and_updates_usage() {
        let server = MockServer::start();
        let mod_jar = server.mock(|when, then| {
            when.method(GET).path("/mod.jar");
            then.status(200).body("mod-bytes");
        });

        let (_dir, mc_folder) = setup_mc_folder();
        let store = MemoryStore::default();
        ensure_default_app_config(&store).unwrap();
        let events = CollectingEvents::default();

        install_modpack(
            &mc_folder,
            InstalledModpack {
                mod_config_version: String::new(),
                quadrant_version: String::new(),
                name: "alpha".to_string(),
                version: "1.20.1".to_string(),
                mod_loader: ModLoader::Fabric,
                mods: vec![InstalledMod {
                    id: "mod-1".to_string(),
                    source: ModSource::Modrinth,
                    download_url: format!("{}/mod.jar", server.base_url()),
                    name: "Test Mod".to_string(),
                    download_count: 0,
                    version: String::new(),
                    mod_type: String::new(),
                    slug: String::new(),
                    thumbnail_urls: Vec::new(),
                    description: String::new(),
                    license: String::new(),
                    mod_icon_url: String::new(),
                }],
            },
            &store,
            &events,
        )
        .await
        .unwrap();

        mod_jar.assert();
        assert!(modpack_path(&mc_folder, "alpha").join("mod.jar").exists());
        assert_eq!(store.get_i64("modrinthUsage").unwrap(), Some(1));
        assert!(
            events
                .events
                .borrow()
                .contains(&BackendEvent::ModpackDownloadProgress(1.0))
        );
    }

    #[cfg(not(target_os = "windows"))]
    #[test]
    fn apply_modpack_creates_symlink() {
        let (_dir, mc_folder) = setup_mc_folder();
        std::fs::create_dir_all(modpack_path(&mc_folder, "alpha")).unwrap();
        apply_modpack(&mc_folder, "alpha").unwrap();
        assert!(mc_folder.join("mods").is_symlink());
    }
}
