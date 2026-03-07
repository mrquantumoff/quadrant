use std::path::{Path, PathBuf};

use anyhow::anyhow;
use futures::StreamExt;
use serde::{Deserialize, Serialize};

use crate::{
    Result,
    events::{BackendEvent, ModProgressPayload},
    models::{InstalledMod, InstalledModpack, LocalModpack, ModLoader, ModSource},
    ports::{EventSink, SettingsStore},
};

use cache::{add_cache_index, file_hash, get_cache_index, init_cache};
#[cfg(feature = "curseforge")]
use curseforge::{
    download_mod_curseforge, get_latest_mod_version_curseforge, search_mods_curseforge,
};
use modrinth::{download_mod_modrinth, get_latest_mod_version_modrinth, search_mods_modrinth};

pub mod cache;
#[cfg(feature = "curseforge")]
pub mod curseforge;
#[cfg(feature = "curseforge")]
pub mod curseforge_fingerprint;
pub mod modrinth;

#[derive(Debug, Clone, Serialize, Deserialize, Eq, PartialEq, Copy)]
pub enum ModType {
    Mod,
    ResourcePack,
    ShaderPack,
    Unknown,
}

impl From<String> for ModType {
    fn from(value: String) -> Self {
        match value.to_lowercase().as_str() {
            "shader" => Self::ShaderPack,
            "mod" => Self::Mod,
            "resourcepack" => Self::ResourcePack,
            _ => Self::Unknown,
        }
    }
}

impl ModType {
    pub fn curseforge_id(&self) -> i32 {
        match *self {
            Self::Mod => 6,
            Self::ResourcePack => 12,
            Self::ShaderPack => 6552,
            Self::Unknown => 999,
        }
    }

    pub fn from_curseforge_class(class_id: i64) -> Self {
        match class_id {
            6 => Self::Mod,
            12 => Self::ResourcePack,
            6552 => Self::ShaderPack,
            _ => Self::Unknown,
        }
    }
}

impl std::fmt::Display for ModType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let label = match *self {
            Self::Mod => "mod",
            Self::ResourcePack => "resourcepack",
            Self::ShaderPack => "shader",
            Self::Unknown => "unknown",
        };
        f.write_str(label)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Mod {
    pub name: String,
    pub id: String,
    pub download_count: i64,
    pub version: String,
    pub mod_type: ModType,
    pub source: ModSource,
    pub slug: String,
    pub thumbnail_urls: Vec<String>,
    pub url: String,
    pub description: String,
    pub license: String,
    pub mod_icon_url: String,
    pub downloadable: bool,
    pub show_previous_version: bool,
    pub new_version: Option<UniversalModFile>,
    pub deleteable: bool,
    pub autoinstallable: bool,
    pub selectable: bool,
    pub modpack: Option<String>,
    pub select_url: Option<String>,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct MinecraftVersion {
    pub version: String,
    pub version_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UniversalModFile {
    pub id: Option<String>,
    pub file_name: String,
    pub download_url: String,
    pub sha1: String,
    pub size: u64,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GlobalSearchModsArgs {
    pub source: ModSource,
    pub query: String,
    pub mod_type: String,
    pub filter_on: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct SearchModsArgs {
    pub query: String,
    pub mod_type: String,
    pub filter_on: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GetModArgs {
    pub id: String,
    pub downloadable: bool,
    pub show_previous_version: bool,
    pub deletable: bool,
    pub version_target: String,
    pub mod_loader: ModLoader,
    pub modpack: String,
    pub selectable: bool,
    pub select_url: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct IdentifiedMod {
    pub installed_mod: InstalledMod,
    pub file_name: String,
}

pub fn get_user_agent() -> String {
    format!(
        "mrquantumoff/quadrant/v{} (mrquantumoff.dev) (QUADRANT NEXT)",
        env!("CARGO_PKG_VERSION")
    )
}

pub async fn get_versions() -> Result<Vec<MinecraftVersion>> {
    let response = reqwest::Client::new()
        .get("https://api.modrinth.com/v2/tag/game_version")
        .header("User-Agent", get_user_agent())
        .send()
        .await?;
    let body: Vec<MinecraftVersion> = response.json().await?;
    Ok(body
        .into_iter()
        .filter(|version| version.version_type == "release" && !version.version.is_empty())
        .collect())
}

pub async fn check_mod_updates(
    mod_to_update: Mod,
    minecraft_version: String,
    mod_loader: ModLoader,
    modpack: LocalModpack,
    show_unupgradeable_mods: bool,
) -> Result<Option<Mod>> {
    let mut new_mod = mod_to_update.clone();
    let existing_mod = modpack.mods.iter().find(|mod_| mod_.id == mod_to_update.id);

    new_mod.show_previous_version = true;
    new_mod.deleteable = false;
    new_mod.autoinstallable = true;

    match mod_to_update.source {
        ModSource::CurseForge => {
            #[cfg(feature = "curseforge")]
            {
                if let Some(latest_file) = get_latest_mod_version_curseforge(
                    mod_to_update.id,
                    minecraft_version,
                    mod_loader,
                    mod_to_update.mod_type,
                    None,
                )
                .await?
                {
                    new_mod.new_version = Some(latest_file.into());
                }
            }
            #[cfg(not(feature = "curseforge"))]
            {
                return Ok(None);
            }
        }
        ModSource::Modrinth => {
            if let Some(latest_file) = get_latest_mod_version_modrinth(
                mod_to_update.id,
                minecraft_version,
                mod_loader,
                mod_to_update.mod_type,
            )
            .await?
            {
                new_mod.new_version = Some(latest_file.into());
            }
        }
        ModSource::Online => {}
    }

    if let (Some(existing_mod), Some(new_file)) = (existing_mod, new_mod.new_version.clone()) {
        if existing_mod.download_url != new_file.download_url {
            new_mod.downloadable = true;
        }
        if existing_mod.download_url == new_file.download_url && !show_unupgradeable_mods {
            return Ok(None);
        }
    }

    Ok(Some(new_mod))
}

pub async fn search_mods(
    args: GlobalSearchModsArgs,
    settings: &impl SettingsStore,
) -> Result<Vec<Mod>> {
    let search_args = SearchModsArgs {
        query: args.query,
        mod_type: args.mod_type,
        filter_on: args.filter_on,
    };

    let mut mods = match args.source {
        ModSource::CurseForge => {
            #[cfg(feature = "curseforge")]
            {
                search_mods_curseforge(settings, search_args).await?
            }
            #[cfg(not(feature = "curseforge"))]
            {
                Vec::new()
            }
        }
        ModSource::Modrinth => search_mods_modrinth(settings, search_args).await?,
        ModSource::Online => Vec::new(),
    };

    mods.sort_by(|a, b| b.download_count.cmp(&a.download_count));
    Ok(mods)
}

pub fn get_mod_url(slug: String, mod_type: ModType, source: ModSource) -> String {
    let base_url = match source {
        ModSource::CurseForge => "https://curseforge.com/minecraft",
        ModSource::Modrinth => "https://modrinth.com",
        ModSource::Online => "",
    };

    let mod_type = match source {
        ModSource::CurseForge => match mod_type {
            ModType::Mod => "mc-mods",
            ModType::ResourcePack => "texture-packs",
            ModType::ShaderPack => "customization",
            ModType::Unknown => "",
        },
        ModSource::Modrinth => match mod_type {
            ModType::Mod => "mod",
            ModType::ResourcePack => "resourcepack",
            ModType::ShaderPack => "shader",
            ModType::Unknown => "unknown",
        },
        ModSource::Online => "",
    };

    format!("{}/{}/{}", base_url, mod_type, slug)
}

pub fn get_user_url(username: String, source: ModSource) -> String {
    let base_url = match source {
        ModSource::CurseForge => "https://curseforge.com/members",
        ModSource::Modrinth => "https://modrinth.com/user",
        ModSource::Online => "",
    };

    format!("{}/{}", base_url, username)
}

pub async fn install_mod(
    mc_folder: &Path,
    existing_modpacks: &[LocalModpack],
    settings: &impl SettingsStore,
    event_sink: &impl EventSink,
    id: String,
    minecraft_version: String,
    mod_loader: ModLoader,
    source: ModSource,
    modpack: Option<String>,
    mod_type: ModType,
    #[allow(unused_variables)] file_id: Option<String>,
) -> Result<Option<LocalModpack>> {
    let download_path = match source {
        ModSource::CurseForge => {
            #[cfg(feature = "curseforge")]
            {
                download_mod_curseforge(
                    settings,
                    event_sink,
                    id.clone(),
                    minecraft_version,
                    mod_loader,
                    mod_type,
                    file_id,
                )
                .await?
            }
            #[cfg(not(feature = "curseforge"))]
            {
                return Err(anyhow!("CurseForge is not enabled"));
            }
        }
        ModSource::Modrinth => {
            download_mod_modrinth(
                settings,
                event_sink,
                id.clone(),
                minecraft_version,
                mod_loader,
                mod_type,
            )
            .await?
        }
        ModSource::Online => unimplemented!(),
    };

    event_sink.publish(BackendEvent::ModInstallProgress(ModProgressPayload {
        mod_id: id.clone(),
        progress: 50,
    }))?;

    let updated_modpack = install_local_file(
        mc_folder,
        existing_modpacks,
        download_path.0,
        download_path.1,
        mod_type,
        modpack,
        id.clone(),
        source,
    )?;

    event_sink.publish(BackendEvent::ModInstallProgress(ModProgressPayload {
        mod_id: id,
        progress: 100,
    }))?;

    Ok(updated_modpack)
}

pub async fn get_file(
    file: UniversalModFile,
    id: String,
    event_sink: &impl EventSink,
) -> Result<(PathBuf, String)> {
    if let Some(cached_file) = get_cache_index(file.sha1.clone()).await? {
        let cached_file_bytes = std::fs::read(&cached_file.file_name).map_err(|error| {
            let _ = futures::executor::block_on(init_cache());
            anyhow!(error)
        })?;
        let file_path = add_cache_index(
            file.file_name.clone(),
            cached_file_bytes.as_slice(),
            file.sha1.clone(),
        )
        .await?;
        event_sink.publish(BackendEvent::ModDownloadProgress(ModProgressPayload {
            mod_id: id,
            progress: 100,
        }))?;
        return Ok((file_path, file.download_url));
    }

    let client = reqwest::Client::new();
    let request = client
        .get(&file.download_url)
        .header("User-Agent", get_user_agent())
        .build()?;
    let mut body = client.execute(request).await?.bytes_stream();
    let mut file_bytes = Vec::new();
    while let Some(Ok(new_bytes)) = body.next().await {
        file_bytes.append(&mut new_bytes.to_vec());
        let progress = ((file_bytes.len() as f64 / file.size as f64) * 100_f64).round() as i32;
        event_sink.publish(BackendEvent::ModDownloadProgress(ModProgressPayload {
            mod_id: id.clone(),
            progress,
        }))?;
    }
    event_sink.publish(BackendEvent::ModDownloadProgress(ModProgressPayload {
        mod_id: id,
        progress: 100,
    }))?;

    let hash = file_hash(file_bytes.as_slice());
    let file_path = add_cache_index(file.file_name.clone(), &file_bytes, hash).await?;
    Ok((file_path, file.download_url))
}

pub fn install_local_file(
    mc_folder: &Path,
    existing_modpacks: &[LocalModpack],
    file: PathBuf,
    download_url: String,
    mod_type: ModType,
    modpack: Option<String>,
    id: String,
    source: ModSource,
) -> Result<Option<LocalModpack>> {
    let local_mod = InstalledMod {
        id: id.clone(),
        source,
        download_url,
    };

    let (target_path, updated_modpack) = match mod_type {
        ModType::Mod => {
            let modpack_name = modpack.expect("modpackRequired");
            let mut modpack = existing_modpacks
                .iter()
                .find(|modpack| modpack.name == modpack_name)
                .cloned()
                .ok_or_else(|| anyhow!("Modpack not found"))?;
            if modpack.mods.iter().any(|mod_| mod_.id == id) {
                modpack.mods.retain(|mod_| mod_.id != id);
            }
            modpack.mods.push(local_mod.clone());

            std::fs::write(
                crate::models::modpack_path(mc_folder, &modpack_name).join("modConfig.json"),
                serde_json::to_string_pretty(&InstalledModpack::from(modpack.clone()))?,
            )?;

            (
                crate::models::modpack_path(mc_folder, &modpack_name)
                    .join(file.file_name().unwrap()),
                Some(modpack),
            )
        }
        ModType::ResourcePack => (
            mc_folder
                .join("resourcepacks")
                .join(file.file_name().unwrap()),
            None,
        ),
        ModType::ShaderPack => (
            mc_folder
                .join("shaderpacks")
                .join(file.file_name().unwrap()),
            None,
        ),
        ModType::Unknown => return Err(anyhow!("unsupportedDownload")),
    };

    if let Some(parent) = target_path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::copy(file, target_path)?;
    Ok(updated_modpack)
}

pub async fn install_remote_file(
    mc_folder: &Path,
    existing_modpacks: &[LocalModpack],
    event_sink: &impl EventSink,
    file: UniversalModFile,
    mod_type: ModType,
    modpack: Option<String>,
    source: ModSource,
    id: String,
) -> Result<Option<LocalModpack>> {
    let downloaded_file = get_file(file, id.clone(), event_sink).await?;
    install_local_file(
        mc_folder,
        existing_modpacks,
        downloaded_file.0,
        downloaded_file.1,
        mod_type,
        modpack,
        id,
        source,
    )
}

pub async fn identify_modpack(
    mc_folder: &Path,
    modpack: String,
    curseforge_enabled: bool,
    modrinth_enabled: bool,
) -> Result<Vec<IdentifiedMod>> {
    let mut mods = Vec::new();
    if curseforge_enabled {
        #[cfg(feature = "curseforge")]
        {
            if let Ok(mut curse_mods) =
                curseforge::identify_modpack_curseforge(&mc_folder.to_path_buf(), modpack.clone())
                    .await
            {
                mods.append(&mut curse_mods);
            }
        }
    }
    if modrinth_enabled {
        let mut modrinth_mods =
            modrinth::identify_modpack_modrinth(&mc_folder.to_path_buf(), modpack).await?;
        mods.append(&mut modrinth_mods);
    }
    Ok(mods)
}
