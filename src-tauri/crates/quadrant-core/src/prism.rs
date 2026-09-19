//! Prism Launcher instance discovery, modpack application, and component sync.
//!
//! Which modpack an instance uses is derived from the target of its
//! `<game dir>/mods` symlink, the same way [`crate::modpacks::get_modpacks`]
//! derives `is_applied` for the Minecraft folder. Nothing about the pairing is
//! persisted, so a link changed outside Quadrant is read correctly.

use crate::{
    Result,
    error::ErrorCode,
    mc_mod::http::provider_cached_client,
    models::{LocalModpack, ModLoader, is_single_path_component, modpack_path},
    modpacks::{
        MODS_BACKUP_PREFIX, link_mods_folder, mods_link_target, validate_modpack_name,
        write_file_atomically,
    },
};
use chrono::{DateTime, FixedOffset};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::path::{Path, PathBuf};

const MINECRAFT_UID: &str = "net.minecraft";

/// The only `mmc-pack.json` layout Prism itself accepts. Quadrant never writes
/// this field, it only refuses to touch a manifest that does not declare it.
const PACK_FORMAT_VERSION: i64 = 1;

/// The Prism component uid for every loader Prism can install. A loader that is
/// not in this table has no Prism component, and its components are left alone.
const LOADER_COMPONENTS: &[(ModLoader, &str)] = &[
    (ModLoader::Fabric, "net.fabricmc.fabric-loader"),
    (ModLoader::Quilt, "org.quiltmc.quilt-loader"),
    (ModLoader::Forge, "net.minecraftforge"),
    (ModLoader::NeoForge, "net.neoforged"),
];

/// A Prism Launcher instance as Quadrant sees it.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct PrismInstance {
    /// Instance folder name, which is also its stable identifier.
    pub id: String,
    /// Display name from `instance.cfg`, falling back to the folder name.
    pub name: String,
    /// Version of the `net.minecraft` component, if the instance declares one.
    pub minecraft_version: Option<String>,
    /// Loader derived from the instance's loader component.
    pub mod_loader: ModLoader,
    /// Version of that loader component.
    pub mod_loader_version: Option<String>,
    /// Modpack the instance's `mods` folder currently links to.
    pub applied_modpack: Option<String>,
}

/// The Prism component uid for `loader`, if Prism installs that loader.
pub fn loader_component_uid(loader: ModLoader) -> Option<&'static str> {
    LOADER_COMPONENTS
        .iter()
        .find(|(candidate, _)| *candidate == loader)
        .map(|(_, uid)| *uid)
}

fn loader_for_component_uid(uid: &str) -> Option<ModLoader> {
    LOADER_COMPONENTS
        .iter()
        .find(|(_, candidate)| *candidate == uid)
        .map(|(loader, _)| *loader)
}

/// Reads `key=value` out of a Prism config file. Prism writes flat INI without
/// sections, so the first match wins and the value is everything after the `=`.
///
/// Qt quotes a value containing `;`, `=` or `,`, so one surrounding pair of
/// double quotes is stripped.
fn ini_value(contents: &str, key: &str) -> Option<String> {
    contents.lines().find_map(|line| {
        let (name, value) = line.split_once('=')?;
        if name.trim() != key {
            return None;
        }
        let value = value.trim();
        Some(
            value
                .strip_prefix('"')
                .and_then(|value| value.strip_suffix('"'))
                .unwrap_or(value)
                .to_string(),
        )
    })
}

fn read_ini_value(path: &Path, key: &str) -> Option<String> {
    ini_value(&std::fs::read_to_string(path).ok()?, key)
}

/// Well-known Prism Launcher data directories for the current platform.
pub fn default_data_dirs() -> Vec<PathBuf> {
    let mut candidates = Vec::new();
    if let Some(data_dir) = dirs::data_dir() {
        candidates.push(data_dir.join("PrismLauncher"));
    }
    #[cfg(target_os = "windows")]
    if let Some(home) = dirs::home_dir() {
        candidates.push(home.join("scoop").join("persist").join("prismlauncher"));
    }
    #[cfg(target_os = "linux")]
    if let Some(home) = dirs::home_dir() {
        candidates.push(
            home.join(".var")
                .join("app")
                .join("org.prismlauncher.PrismLauncher")
                .join("data")
                .join("PrismLauncher"),
        );
    }
    candidates
}

/// Resolves the Prism data directory, preferring an explicit override.
///
/// An override that does not exist resolves to `None` rather than silently
/// falling back, so a mistyped path is visible as "Prism not found".
pub fn find_data_dir(override_dir: Option<PathBuf>) -> Option<PathBuf> {
    if let Some(override_dir) = override_dir {
        return override_dir.is_dir().then_some(override_dir);
    }
    default_data_dirs()
        .into_iter()
        .find(|dir| dir.join("prismlauncher.cfg").is_file() || dir.join("instances").is_dir())
}

/// Resolves the instances folder of a Prism data directory.
pub fn instances_dir(data_dir: &Path) -> PathBuf {
    match read_ini_value(&data_dir.join("prismlauncher.cfg"), "InstanceDir")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
    {
        Some(dir) if dir.is_absolute() => dir,
        Some(dir) => data_dir.join(dir),
        None => data_dir.join("instances"),
    }
}

/// Resolves an instance's Minecraft directory the way Prism's `gameRoot()` does.
pub fn game_dir(instance_dir: &Path) -> PathBuf {
    let legacy = instance_dir.join(".minecraft");
    if legacy.is_dir() && !instance_dir.join("minecraft").is_dir() {
        return legacy;
    }
    instance_dir.join("minecraft")
}

/// Resolves an existing instance's folder, rejecting an id that is not a single
/// path component.
pub fn resolve_instance_dir(instances_dir: &Path, instance_id: &str) -> Result<PathBuf> {
    if !is_single_path_component(instance_id) {
        return Err(anyhow::Error::from(ErrorCode::InvalidRequest));
    }
    let dir = instances_dir.join(instance_id);
    if !dir.join("mmc-pack.json").is_file() {
        return Err(anyhow::Error::from(ErrorCode::PrismInstanceMissing));
    }
    Ok(dir)
}

/// Reads an instance's `mmc-pack.json` as raw JSON.
pub fn read_pack_manifest(instances_dir: &Path, instance_id: &str) -> Result<Value> {
    let path = resolve_instance_dir(instances_dir, instance_id)?.join("mmc-pack.json");
    Ok(serde_json::from_slice(&std::fs::read(path)?)?)
}

/// Lists the Prism instances under `instances_dir`, sorted by display name.
pub fn list_instances(instances_dir: &Path, mc_folder: &Path) -> Result<Vec<PrismInstance>> {
    let mut instances = Vec::new();
    if !instances_dir.is_dir() {
        return Ok(instances);
    }

    for entry in std::fs::read_dir(instances_dir)? {
        let entry = entry?;
        let dir = entry.path();
        if !dir.join("instance.cfg").is_file() || !dir.join("mmc-pack.json").is_file() {
            continue;
        }
        let id = entry.file_name().to_string_lossy().to_string();
        // One garbled instance must not blank the listing; the user's other
        // instances stay selectable.
        match read_instance(&dir, id.clone(), mc_folder) {
            Ok(instance) => instances.push(instance),
            Err(error) => log::warn!("Skipping Prism instance \"{id}\": {error}"),
        }
    }

    instances.sort_by(|left, right| left.name.cmp(&right.name));
    Ok(instances)
}

fn read_instance(dir: &Path, id: String, mc_folder: &Path) -> Result<PrismInstance> {
    let pack: Value = serde_json::from_slice(&std::fs::read(dir.join("mmc-pack.json"))?)?;
    validate_pack(&pack)?;
    let components = pack["components"]
        .as_array()
        .ok_or_else(|| anyhow::Error::from(ErrorCode::PrismInstanceUnreadable))?;

    let minecraft_version = components
        .iter()
        .find(|component| component["uid"] == MINECRAFT_UID)
        .and_then(|component| component["version"].as_str())
        .map(ToOwned::to_owned);

    let (mod_loader, mod_loader_version) = components
        .iter()
        .find_map(|component| {
            let loader = loader_for_component_uid(component["uid"].as_str()?)?;
            Some((loader, component["version"].as_str().map(ToOwned::to_owned)))
        })
        .unwrap_or((ModLoader::Unknown, None));

    let mods_path = game_dir(dir).join("mods");
    let modpacks_folder = mc_folder.join("modpacks");
    let applied_modpack = mods_link_target(&mods_path)
        // A link left behind by a deleted modpack names a pack that no longer
        // exists, so it counts as not applied.
        .filter(|target| target.parent() == Some(modpacks_folder.as_path()) && target.is_dir())
        .and_then(|target| {
            target
                .file_name()
                .map(|name| name.to_string_lossy().to_string())
        });

    Ok(PrismInstance {
        name: read_ini_value(&dir.join("instance.cfg"), "name")
            .filter(|name| !name.is_empty())
            .unwrap_or_else(|| id.clone()),
        id,
        minecraft_version,
        mod_loader,
        mod_loader_version,
        applied_modpack,
    })
}

/// Checks the parts of `mmc-pack.json` Quadrant relies on. `formatVersion` is
/// Prism's own compatibility gate, so a manifest that does not declare the
/// version Prism accepts is left untouched rather than rewritten blind.
fn validate_pack(pack: &Value) -> Result<()> {
    if pack["formatVersion"].as_i64() != Some(PACK_FORMAT_VERSION) || !pack["components"].is_array()
    {
        return Err(anyhow::Error::from(ErrorCode::PrismInstanceUnreadable));
    }
    Ok(())
}

fn components_mut(pack: &mut Value) -> Result<&mut Vec<Value>> {
    validate_pack(pack)?;
    pack.as_object_mut()
        .and_then(|object| object.get_mut("components"))
        .and_then(Value::as_array_mut)
        .ok_or_else(|| anyhow::Error::from(ErrorCode::PrismInstanceUnreadable))
}

/// Drops the `cached*` fields Prism fills in, so it re-resolves them for the
/// version that was just written instead of showing the previous one.
fn drop_cached_fields(component: &mut Value) {
    if let Some(object) = component.as_object_mut() {
        object.retain(|key, _| !key.starts_with("cached"));
    }
}

/// A modpack without a manifest reports `-` as its version, which carries no
/// information about what the instance should run.
fn is_syncable_version(minecraft_version: &str) -> bool {
    !minecraft_version.is_empty() && minecraft_version != "-"
}

/// Whether Forge-family loader builds must be re-resolved for a new Minecraft
/// version. Fabric and Quilt loader builds are Minecraft-version independent.
fn loader_is_minecraft_specific(loader: ModLoader) -> bool {
    matches!(loader, ModLoader::Forge | ModLoader::NeoForge)
}

/// Aligns an instance's components with a modpack's Minecraft version and mod
/// loader, reporting whether anything changed.
///
/// The manifest is edited as raw JSON so fields Quadrant does not model survive
/// the rewrite. Returning `false` means the caller must not write the file, and
/// an error can leave `pack` partly edited, so it must be discarded.
pub fn sync_components(
    pack: &mut Value,
    minecraft_version: &str,
    loader: ModLoader,
    loader_version: Option<&str>,
) -> Result<bool> {
    if !is_syncable_version(minecraft_version) {
        return Ok(false);
    }
    let components = components_mut(pack)?;
    let mut changed = false;
    let mut minecraft_changed = false;

    match components
        .iter()
        .position(|component| component["uid"] == MINECRAFT_UID)
    {
        Some(index) => {
            let component = &mut components[index];
            if component["version"] != minecraft_version {
                component["version"] = Value::String(minecraft_version.to_string());
                drop_cached_fields(component);
                minecraft_changed = true;
            }
            // Without `important` Prism lets the user remove Minecraft from the
            // instance, and skips its own re-resolve when the version changes.
            if component["important"] != true {
                component["important"] = Value::Bool(true);
                changed = true;
            }
        }
        None => {
            components.push(json!({
                "uid": MINECRAFT_UID,
                "version": minecraft_version,
                "important": true,
            }));
            minecraft_changed = true;
        }
    }
    changed |= minecraft_changed;

    if let Some(uid) = loader_component_uid(loader) {
        let before = components.len();
        components.retain(|component| {
            component["uid"].as_str().is_none_or(|existing| {
                existing == uid || loader_for_component_uid(existing).is_none()
            })
        });
        changed |= components.len() != before;

        let rebuild = loader_is_minecraft_specific(loader) && minecraft_changed;
        match components
            .iter()
            .position(|component| component["uid"] == uid)
        {
            Some(index) if rebuild => {
                let version = loader_version.ok_or(ErrorCode::PrismLoaderVersionRequired)?;
                if components[index]["version"] != version {
                    components[index]["version"] = Value::String(version.to_string());
                    drop_cached_fields(&mut components[index]);
                    changed = true;
                }
            }
            Some(_) => {}
            None => {
                let version = loader_version.ok_or(ErrorCode::PrismLoaderVersionRequired)?;
                components.push(json!({ "uid": uid, "version": version }));
                changed = true;
            }
        }
    }

    if minecraft_changed {
        // LWJGL and the intermediary mappings are pinned to what Prism resolved
        // for the previous Minecraft version, so dropping them makes Prism
        // re-resolve on the next launch. A new Minecraft version has to be
        // downloaded online anyway, whereas a loader-only change leaves them in
        // place so an already cached instance still launches offline.
        components.retain(|component| component["dependencyOnly"] != true);
    }
    Ok(changed)
}

/// Whether [`sync_components`] would need a `loader_version` for this target,
/// so a caller only reaches the network when the answer is used.
pub fn needs_loader_version(pack: &Value, minecraft_version: &str, loader: ModLoader) -> bool {
    if !is_syncable_version(minecraft_version) {
        return false;
    }
    let Some(uid) = loader_component_uid(loader) else {
        return false;
    };
    let Some(components) = pack["components"].as_array() else {
        return true;
    };
    let minecraft_changes = components
        .iter()
        .find(|component| component["uid"] == MINECRAFT_UID)
        .is_none_or(|component| component["version"] != minecraft_version);

    !components.iter().any(|component| component["uid"] == uid)
        || (loader_is_minecraft_specific(loader) && minecraft_changes)
}

/// Points an instance's `mods` folder at a modpack and syncs the instance's
/// Minecraft version and mod loader to match it.
pub fn apply_modpack_to_instance(
    mc_folder: &Path,
    instances_dir: &Path,
    instance_id: &str,
    modpack: &LocalModpack,
    loader_version: Option<&str>,
) -> Result<()> {
    validate_modpack_name(&modpack.name)?;
    let instance_folder = resolve_instance_dir(instances_dir, instance_id)?;
    let modpack_dir = modpack_path(mc_folder, &modpack.name);
    if !modpack_dir.is_dir() {
        return Err(anyhow::Error::from(ErrorCode::ModpackMissing));
    }
    log::info!(
        "Applying modpack \"{}\" to Prism instance \"{instance_id}\"",
        modpack.name
    );

    // Compute the new manifest before touching the filesystem, so a rejected
    // manifest or a missing loader version leaves the instance untouched rather
    // than linked but out of sync.
    let manifest = instance_folder.join("mmc-pack.json");
    let mut pack: Value = serde_json::from_slice(&std::fs::read(&manifest)?)?;
    let pack_changed = sync_components(
        &mut pack,
        &modpack.version,
        modpack.mod_loader,
        loader_version,
    )?;

    let game_folder = game_dir(&instance_folder);
    std::fs::create_dir_all(&game_folder)?;
    link_mods_folder(&game_folder.join("mods"), &modpack_dir, &game_folder)?;

    if pack_changed {
        write_file_atomically(&manifest, serde_json::to_string_pretty(&pack)?)?;
    }
    Ok(())
}

/// Unlinks an instance from its modpack and gives it back the `mods` folder
/// that applying set aside, or an empty one if there was none. A no-op when the
/// instance is not linked.
pub fn detach_instance(instances_dir: &Path, instance_id: &str) -> Result<()> {
    let game_folder = game_dir(&resolve_instance_dir(instances_dir, instance_id)?);
    let mods_path = game_folder.join("mods");
    if !mods_path.is_symlink() {
        return Ok(());
    }
    log::info!("Detaching Prism instance \"{instance_id}\" from its modpack");
    std::fs::remove_dir_all(&mods_path)?;

    // Backup names end in a sortable timestamp, so the greatest is the newest.
    let newest_backup = std::fs::read_dir(&game_folder)?
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path())
        .filter(|path| {
            path.is_dir()
                && path
                    .file_name()
                    .is_some_and(|name| name.to_string_lossy().starts_with(MODS_BACKUP_PREFIX))
        })
        .max();
    match newest_backup {
        Some(backup) => std::fs::rename(backup, &mods_path)?,
        None => std::fs::create_dir_all(&mods_path)?,
    }
    Ok(())
}

/// Every root the named modpack is applied to, as a place to install content
/// that lives beside `mods` rather than inside it.
///
/// Falls back to `mc_folder` when the modpack is applied nowhere, which keeps
/// resource pack and shader installs working for an unapplied pack.
pub fn content_roots(
    mc_folder: &Path,
    instances_dir: Option<&Path>,
    modpack: &str,
) -> Vec<PathBuf> {
    if modpack.is_empty() {
        return vec![mc_folder.to_path_buf()];
    }

    let mut roots = Vec::new();
    if mods_link_target(&mc_folder.join("mods"))
        .is_some_and(|target| target == modpack_path(mc_folder, modpack))
    {
        roots.push(mc_folder.to_path_buf());
    }

    if let Some(instances_dir) = instances_dir {
        match list_instances(instances_dir, mc_folder) {
            Ok(instances) => roots.extend(
                instances
                    .iter()
                    .filter(|instance| instance.applied_modpack.as_deref() == Some(modpack))
                    .map(|instance| game_dir(&instances_dir.join(&instance.id))),
            ),
            Err(error) => {
                log::warn!("Ignoring Prism instances while resolving content roots: {error}");
            }
        }
    }

    if roots.is_empty() {
        roots.push(mc_folder.to_path_buf());
    }
    roots
}

fn prism_meta_base() -> String {
    #[cfg(test)]
    if let Ok(base_url) = std::env::var("QUADRANT_TEST_PRISM_META_BASE") {
        return base_url;
    }

    "https://meta.prismlauncher.org".to_string()
}

#[derive(Deserialize)]
struct MetaIndex {
    #[serde(default)]
    versions: Vec<MetaVersion>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct MetaVersion {
    version: String,
    #[serde(default)]
    recommended: bool,
    #[serde(default)]
    release_time: String,
    #[serde(default)]
    requires: Vec<MetaRequirement>,
}

impl MetaVersion {
    fn released_at(&self) -> Option<DateTime<FixedOffset>> {
        DateTime::parse_from_rfc3339(&self.release_time).ok()
    }

    fn supports(&self, minecraft_version: &str) -> bool {
        self.requires
            .iter()
            .filter(|requirement| requirement.uid == MINECRAFT_UID)
            .all(|requirement| requirement.equals.as_deref() == Some(minecraft_version))
    }
}

#[derive(Deserialize)]
struct MetaRequirement {
    uid: String,
    #[serde(default)]
    equals: Option<String>,
}

/// Looks up the loader build Prism should use for a Minecraft version.
///
/// Prefers the newest build upstream marks as recommended, falling back to the
/// newest compatible build of any kind.
pub async fn resolve_loader_version(loader: ModLoader, minecraft_version: &str) -> Result<String> {
    let uid = loader_component_uid(loader).ok_or(ErrorCode::PrismLoaderVersionNotFound)?;
    let index: MetaIndex = provider_cached_client()
        .get(format!("{}/v1/{uid}/index.json", prism_meta_base()))
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;

    let mut candidates: Vec<&MetaVersion> = index
        .versions
        .iter()
        .filter(|version| version.supports(minecraft_version))
        .collect();
    if candidates.iter().any(|version| version.recommended) {
        candidates.retain(|version| version.recommended);
    }

    let newest = candidates
        .into_iter()
        .max_by_key(|version| version.released_at())
        .ok_or(ErrorCode::PrismLoaderVersionNotFound)?;
    Ok(newest.version.clone())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mc_mod::http::{PROVIDER_HTTP_TEST_MUTEX, clear_provider_http_cache};
    use httpmock::prelude::*;
    use tempfile::{TempDir, tempdir};

    fn pack_with(components: Value) -> Value {
        json!({ "formatVersion": 1, "components": components })
    }

    fn uids(pack: &Value) -> Vec<String> {
        pack["components"]
            .as_array()
            .unwrap()
            .iter()
            .map(|component| component["uid"].as_str().unwrap().to_string())
            .collect()
    }

    fn component<'a>(pack: &'a Value, uid: &str) -> &'a Value {
        pack["components"]
            .as_array()
            .unwrap()
            .iter()
            .find(|component| component["uid"] == uid)
            .unwrap_or_else(|| panic!("{uid} should be present"))
    }

    fn write_instance(instances_dir: &Path, id: &str, name: &str, pack: &Value) -> PathBuf {
        let dir = instances_dir.join(id);
        std::fs::create_dir_all(dir.join("minecraft")).unwrap();
        std::fs::write(
            dir.join("instance.cfg"),
            format!("InstanceType=OneSix\nname={name}\n"),
        )
        .unwrap();
        std::fs::write(
            dir.join("mmc-pack.json"),
            serde_json::to_string_pretty(pack).unwrap(),
        )
        .unwrap();
        dir
    }

    fn setup_dirs() -> (TempDir, PathBuf, PathBuf) {
        let dir = tempdir().unwrap();
        let mc_folder = dir.path().join(".minecraft");
        let instances_dir = dir.path().join("instances");
        std::fs::create_dir_all(mc_folder.join("modpacks")).unwrap();
        std::fs::create_dir_all(&instances_dir).unwrap();
        (dir, mc_folder, instances_dir)
    }

    fn local_modpack(name: &str, version: &str, mod_loader: ModLoader) -> LocalModpack {
        LocalModpack {
            name: name.to_string(),
            version: version.to_string(),
            mods: Vec::new(),
            mod_loader,
            is_applied: false,
            last_synced: 0,
            modpack_id: None,
            unknown_mods: false,
        }
    }

    #[test]
    fn sync_components_updates_minecraft_and_clears_derived_state() {
        let mut pack = pack_with(json!([
            {
                "uid": MINECRAFT_UID,
                "version": "1.20.1",
                "important": true,
                "cachedName": "Minecraft",
                "cachedVersion": "1.20.1"
            },
            { "uid": "org.lwjgl3", "version": "3.3.2", "dependencyOnly": true },
            { "uid": "net.fabricmc.intermediary", "version": "1.20.1", "dependencyOnly": true }
        ]));

        assert!(sync_components(&mut pack, "1.21.1", ModLoader::Unknown, None).unwrap());

        assert_eq!(uids(&pack), [MINECRAFT_UID]);
        let minecraft = component(&pack, MINECRAFT_UID);
        assert_eq!(minecraft["version"], "1.21.1");
        assert_eq!(minecraft["important"], true);
        assert!(minecraft.get("cachedName").is_none());
        assert!(minecraft.get("cachedVersion").is_none());
    }

    #[test]
    fn sync_components_keeps_dependencies_when_only_the_loader_changes() {
        let mut pack = pack_with(json!([
            { "uid": MINECRAFT_UID, "version": "1.21.1", "important": true },
            { "uid": "org.lwjgl3", "version": "3.3.3", "dependencyOnly": true },
            { "uid": "net.fabricmc.intermediary", "version": "1.21.1", "dependencyOnly": true },
            { "uid": "net.fabricmc.fabric-loader", "version": "0.16.9" }
        ]));

        assert!(
            sync_components(&mut pack, "1.21.1", ModLoader::NeoForge, Some("21.1.251")).unwrap()
        );

        assert_eq!(
            uids(&pack),
            [
                MINECRAFT_UID,
                "org.lwjgl3",
                "net.fabricmc.intermediary",
                "net.neoforged"
            ]
        );
    }

    #[test]
    fn sync_components_restores_the_important_flag_on_minecraft() {
        let mut pack = pack_with(json!([{ "uid": MINECRAFT_UID, "version": "1.21.1" }]));

        assert!(sync_components(&mut pack, "1.21.1", ModLoader::Unknown, None).unwrap());
        assert_eq!(component(&pack, MINECRAFT_UID)["important"], true);
        assert!(!sync_components(&mut pack, "1.21.1", ModLoader::Unknown, None).unwrap());
    }

    #[test]
    fn sync_components_refuses_manifests_prism_would_not_accept() {
        for pack in [
            json!({ "components": [] }),
            json!({ "formatVersion": 2, "components": [] }),
            json!({ "formatVersion": "1", "components": [] }),
            json!({ "formatVersion": 1, "components": {} }),
            json!({ "formatVersion": 1 }),
            json!([]),
        ] {
            let mut pack = pack;
            let before = pack.clone();
            assert!(
                sync_components(&mut pack, "1.21.1", ModLoader::Fabric, Some("0.16.9"))
                    .unwrap_err()
                    .to_string()
                    .contains("errorPrismInstanceUnreadable"),
                "{before}"
            );
            assert_eq!(pack, before);
        }
    }

    #[test]
    fn sync_components_keeps_fabric_across_a_minecraft_change() {
        let mut pack = pack_with(json!([
            { "uid": MINECRAFT_UID, "version": "1.20.1" },
            { "uid": "net.fabricmc.fabric-loader", "version": "0.15.0" }
        ]));

        assert!(sync_components(&mut pack, "1.21.1", ModLoader::Fabric, None).unwrap());

        assert_eq!(
            component(&pack, "net.fabricmc.fabric-loader")["version"],
            "0.15.0"
        );
        assert_eq!(component(&pack, MINECRAFT_UID)["version"], "1.21.1");
    }

    #[test]
    fn sync_components_reversions_forge_when_minecraft_changes() {
        let mut pack = pack_with(json!([
            { "uid": MINECRAFT_UID, "version": "1.20.1" },
            { "uid": "net.minecraftforge", "version": "47.2.0", "cachedName": "Forge" }
        ]));

        assert!(
            sync_components(&mut pack, "1.21.1", ModLoader::Forge, None)
                .unwrap_err()
                .to_string()
                .contains("errorPrismLoaderVersionRequired")
        );

        let mut pack = pack_with(json!([
            { "uid": MINECRAFT_UID, "version": "1.20.1" },
            { "uid": "net.minecraftforge", "version": "47.2.0", "cachedName": "Forge" }
        ]));
        assert!(sync_components(&mut pack, "1.21.1", ModLoader::Forge, Some("52.0.2")).unwrap());
        let forge = component(&pack, "net.minecraftforge");
        assert_eq!(forge["version"], "52.0.2");
        assert!(forge.get("cachedName").is_none());
    }

    #[test]
    fn sync_components_keeps_forge_version_when_minecraft_is_unchanged() {
        let mut pack = pack_with(json!([
            { "uid": MINECRAFT_UID, "version": "1.20.1", "important": true },
            { "uid": "net.minecraftforge", "version": "47.2.0" }
        ]));

        assert!(!sync_components(&mut pack, "1.20.1", ModLoader::Forge, None).unwrap());
        assert_eq!(component(&pack, "net.minecraftforge")["version"], "47.2.0");
    }

    #[test]
    fn sync_components_swaps_the_loader() {
        let mut pack = pack_with(json!([
            { "uid": MINECRAFT_UID, "version": "1.21.1" },
            { "uid": "net.fabricmc.fabric-loader", "version": "0.16.9" }
        ]));

        assert!(
            sync_components(&mut pack, "1.21.1", ModLoader::NeoForge, Some("21.1.80")).unwrap()
        );

        assert_eq!(uids(&pack), [MINECRAFT_UID, "net.neoforged"]);
        assert_eq!(component(&pack, "net.neoforged")["version"], "21.1.80");
    }

    #[test]
    fn sync_components_leaves_loaders_prism_does_not_know() {
        for loader in [ModLoader::Unknown, ModLoader::Babric, ModLoader::Rift] {
            let mut pack = pack_with(json!([
                { "uid": MINECRAFT_UID, "version": "1.21.1", "important": true },
                { "uid": "net.fabricmc.fabric-loader", "version": "0.16.9" }
            ]));

            assert!(!sync_components(&mut pack, "1.21.1", loader, None).unwrap());
            assert_eq!(uids(&pack), [MINECRAFT_UID, "net.fabricmc.fabric-loader"]);
        }
    }

    #[test]
    fn sync_components_skips_packs_without_a_manifest_version() {
        for version in ["", "-"] {
            let mut pack = pack_with(json!([{ "uid": MINECRAFT_UID, "version": "1.20.1" }]));
            assert!(!sync_components(&mut pack, version, ModLoader::Forge, None).unwrap());
            assert_eq!(component(&pack, MINECRAFT_UID)["version"], "1.20.1");
        }
    }

    #[test]
    fn sync_components_is_idempotent_and_preserves_unknown_fields() {
        let mut pack = json!({
            "formatVersion": 1,
            "quadrantUnknown": { "keep": true },
            "components": [
                { "uid": MINECRAFT_UID, "version": "1.20.1" },
                { "uid": "org.lwjgl3", "version": "3.3.2", "dependencyOnly": true }
            ]
        });

        assert!(sync_components(&mut pack, "1.21.1", ModLoader::Fabric, Some("0.16.9")).unwrap());
        let after_first = pack.clone();
        assert!(!sync_components(&mut pack, "1.21.1", ModLoader::Fabric, Some("0.16.9")).unwrap());

        assert_eq!(pack, after_first);
        assert_eq!(pack["quadrantUnknown"]["keep"], true);
        assert_eq!(pack["formatVersion"], 1);
        assert_eq!(uids(&pack), [MINECRAFT_UID, "net.fabricmc.fabric-loader"]);
    }

    #[test]
    fn sync_components_adds_a_missing_minecraft_component() {
        let mut pack = pack_with(json!([]));
        assert!(sync_components(&mut pack, "1.21.1", ModLoader::Unknown, None).unwrap());
        let minecraft = component(&pack, MINECRAFT_UID);
        assert_eq!(minecraft["version"], "1.21.1");
        assert_eq!(minecraft["important"], true);
    }

    #[test]
    fn needs_loader_version_only_when_sync_would_use_one() {
        let pack = pack_with(json!([
            { "uid": MINECRAFT_UID, "version": "1.20.1" },
            { "uid": "net.minecraftforge", "version": "47.2.0" }
        ]));

        assert!(!needs_loader_version(&pack, "1.20.1", ModLoader::Forge));
        assert!(needs_loader_version(&pack, "1.21.1", ModLoader::Forge));
        assert!(needs_loader_version(&pack, "1.20.1", ModLoader::Fabric));
        assert!(!needs_loader_version(&pack, "1.20.1", ModLoader::Unknown));
        assert!(!needs_loader_version(&pack, "-", ModLoader::Fabric));

        let fabric = pack_with(json!([
            { "uid": MINECRAFT_UID, "version": "1.20.1" },
            { "uid": "net.fabricmc.fabric-loader", "version": "0.15.0" }
        ]));
        assert!(!needs_loader_version(&fabric, "1.21.1", ModLoader::Fabric));
    }

    #[test]
    fn instances_dir_honours_the_configured_override() {
        let dir = tempdir().unwrap();
        let data_dir = dir.path();
        assert_eq!(instances_dir(data_dir), data_dir.join("instances"));

        std::fs::write(
            data_dir.join("prismlauncher.cfg"),
            "[General]\nApplicationTheme=dark\nInstanceDir=my instances\n",
        )
        .unwrap();
        assert_eq!(instances_dir(data_dir), data_dir.join("my instances"));

        let absolute = dir.path().join("elsewhere");
        std::fs::write(
            data_dir.join("prismlauncher.cfg"),
            format!("InstanceDir={}\n", absolute.display()),
        )
        .unwrap();
        assert_eq!(instances_dir(data_dir), absolute);
    }

    #[test]
    fn game_dir_prefers_dot_minecraft_only_when_minecraft_is_absent() {
        let dir = tempdir().unwrap();
        let instance = dir.path().join("instance");
        std::fs::create_dir_all(&instance).unwrap();
        assert_eq!(game_dir(&instance), instance.join("minecraft"));

        std::fs::create_dir(instance.join(".minecraft")).unwrap();
        assert_eq!(game_dir(&instance), instance.join(".minecraft"));

        std::fs::create_dir(instance.join("minecraft")).unwrap();
        assert_eq!(game_dir(&instance), instance.join("minecraft"));
    }

    #[test]
    fn list_instances_reads_names_versions_and_skips_broken_entries() {
        let (_dir, mc_folder, instances_dir) = setup_dirs();
        write_instance(
            &instances_dir,
            "zulu",
            "Anvil",
            &pack_with(json!([
                { "uid": MINECRAFT_UID, "version": "1.21.1" },
                { "uid": "net.fabricmc.fabric-loader", "version": "0.16.9" }
            ])),
        );
        write_instance(
            &instances_dir,
            "alpha",
            "Zephyr",
            &pack_with(json!([{ "uid": MINECRAFT_UID, "version": "1.20.1" }])),
        );
        let broken = instances_dir.join("broken");
        std::fs::create_dir_all(&broken).unwrap();
        std::fs::write(broken.join("instance.cfg"), "name=Broken\n").unwrap();
        std::fs::write(broken.join("mmc-pack.json"), "{not json").unwrap();
        write_instance(
            &instances_dir,
            "future",
            "Future",
            &json!({ "formatVersion": 2, "components": [] }),
        );
        // A folder that is not an instance at all.
        std::fs::create_dir_all(instances_dir.join("_MMC_TEMP")).unwrap();

        let instances = list_instances(&instances_dir, &mc_folder).unwrap();

        assert_eq!(
            instances
                .iter()
                .map(|instance| (instance.id.as_str(), instance.name.as_str()))
                .collect::<Vec<_>>(),
            [("zulu", "Anvil"), ("alpha", "Zephyr")]
        );
        assert_eq!(instances[0].mod_loader, ModLoader::Fabric);
        assert_eq!(instances[0].mod_loader_version.as_deref(), Some("0.16.9"));
        assert_eq!(instances[0].minecraft_version.as_deref(), Some("1.21.1"));
        assert_eq!(instances[1].mod_loader, ModLoader::Unknown);
        assert!(instances[0].applied_modpack.is_none());
    }

    #[test]
    fn list_instances_falls_back_to_the_folder_name() {
        let (_dir, mc_folder, instances_dir) = setup_dirs();
        let dir = instances_dir.join("nameless");
        std::fs::create_dir_all(dir.join("minecraft")).unwrap();
        std::fs::write(dir.join("instance.cfg"), "InstanceType=OneSix\n").unwrap();
        std::fs::write(dir.join("mmc-pack.json"), pack_with(json!([])).to_string()).unwrap();

        let instances = list_instances(&instances_dir, &mc_folder).unwrap();
        assert_eq!(instances[0].name, "nameless");
    }

    #[cfg(not(target_os = "windows"))]
    #[test]
    fn list_instances_reads_the_applied_modpack_from_a_legacy_game_dir() {
        let (_dir, mc_folder, instances_dir) = setup_dirs();
        let instance = instances_dir.join("legacy");
        std::fs::create_dir_all(instance.join(".minecraft")).unwrap();
        std::fs::write(instance.join("instance.cfg"), "name=Legacy\n").unwrap();
        std::fs::write(
            instance.join("mmc-pack.json"),
            pack_with(json!([{ "uid": MINECRAFT_UID, "version": "1.20.1" }])).to_string(),
        )
        .unwrap();
        let modpack_dir = modpack_path(&mc_folder, "alpha");
        std::fs::create_dir_all(&modpack_dir).unwrap();
        std::os::unix::fs::symlink(&modpack_dir, instance.join(".minecraft").join("mods")).unwrap();

        let instances = list_instances(&instances_dir, &mc_folder).unwrap();
        assert_eq!(instances[0].applied_modpack.as_deref(), Some("alpha"));
    }

    #[cfg(not(target_os = "windows"))]
    #[test]
    fn apply_and_detach_link_and_restore_the_instance_mods_folder() {
        let (_dir, mc_folder, instances_dir) = setup_dirs();
        let instance = write_instance(
            &instances_dir,
            "alpha",
            "Alpha",
            &pack_with(json!([
                { "uid": MINECRAFT_UID, "version": "1.20.1" },
                { "uid": "org.lwjgl3", "version": "3.3.2", "dependencyOnly": true }
            ])),
        );
        let modpack_dir = modpack_path(&mc_folder, "pack");
        std::fs::create_dir_all(&modpack_dir).unwrap();
        let mods_path = instance.join("minecraft").join("mods");
        std::fs::create_dir_all(&mods_path).unwrap();
        std::fs::write(mods_path.join("loose.jar"), "jar").unwrap();

        apply_modpack_to_instance(
            &mc_folder,
            &instances_dir,
            "alpha",
            &local_modpack("pack", "1.21.1", ModLoader::Fabric),
            Some("0.16.9"),
        )
        .unwrap();

        assert!(mods_path.is_symlink());
        assert_eq!(mods_path.read_link().unwrap(), modpack_dir);
        let backup = std::fs::read_dir(instance.join("minecraft"))
            .unwrap()
            .filter_map(|entry| entry.ok())
            .find(|entry| {
                entry
                    .file_name()
                    .to_string_lossy()
                    .starts_with("mods-backup-")
            })
            .expect("the real mods folder should be backed up");
        assert!(backup.path().join("loose.jar").exists());

        let pack: Value =
            serde_json::from_slice(&std::fs::read(instance.join("mmc-pack.json")).unwrap())
                .unwrap();
        assert_eq!(uids(&pack), [MINECRAFT_UID, "net.fabricmc.fabric-loader"]);
        assert_eq!(component(&pack, MINECRAFT_UID)["version"], "1.21.1");
        assert_eq!(
            list_instances(&instances_dir, &mc_folder).unwrap()[0]
                .applied_modpack
                .as_deref(),
            Some("pack")
        );

        detach_instance(&instances_dir, "alpha").unwrap();
        assert!(!mods_path.is_symlink());
        assert!(mods_path.join("loose.jar").exists());
        assert!(!backup.path().exists());
        assert!(modpack_dir.is_dir());
        // Detaching twice must converge on the same state.
        detach_instance(&instances_dir, "alpha").unwrap();
        assert!(mods_path.is_dir());
    }

    #[test]
    fn a_failed_apply_leaves_the_instance_untouched() {
        let (_dir, mc_folder, instances_dir) = setup_dirs();
        let instance = write_instance(
            &instances_dir,
            "alpha",
            "Alpha",
            &pack_with(json!([
                { "uid": MINECRAFT_UID, "version": "1.20.1", "important": true }
            ])),
        );
        std::fs::create_dir_all(modpack_path(&mc_folder, "pack")).unwrap();
        let manifest_before = std::fs::read(instance.join("mmc-pack.json")).unwrap();

        // Forge needs a build for the new Minecraft version and none was resolved.
        assert!(
            apply_modpack_to_instance(
                &mc_folder,
                &instances_dir,
                "alpha",
                &local_modpack("pack", "1.21.1", ModLoader::Forge),
                None,
            )
            .is_err()
        );

        assert_eq!(
            std::fs::read(instance.join("mmc-pack.json")).unwrap(),
            manifest_before
        );
        assert!(!instance.join("minecraft").join("mods").exists());
    }

    #[test]
    fn instance_operations_reject_unknown_and_unsafe_ids() {
        let (_dir, mc_folder, instances_dir) = setup_dirs();
        let modpack = local_modpack("pack", "1.21.1", ModLoader::Fabric);
        std::fs::create_dir_all(modpack_path(&mc_folder, "pack")).unwrap();

        for id in ["ghost", "../escape", "", "a/b"] {
            assert!(
                apply_modpack_to_instance(&mc_folder, &instances_dir, id, &modpack, Some("0.16.9"))
                    .is_err(),
                "{id:?}"
            );
            assert!(detach_instance(&instances_dir, id).is_err(), "{id:?}");
        }
    }

    #[cfg(not(target_os = "windows"))]
    #[test]
    fn content_roots_covers_every_place_a_modpack_is_applied() {
        let (_dir, mc_folder, instances_dir) = setup_dirs();
        let modpack_dir = modpack_path(&mc_folder, "pack");
        std::fs::create_dir_all(&modpack_dir).unwrap();
        write_instance(
            &instances_dir,
            "alpha",
            "Alpha",
            &pack_with(json!([{ "uid": MINECRAFT_UID, "version": "1.21.1" }])),
        );
        write_instance(
            &instances_dir,
            "beta",
            "Beta",
            &pack_with(json!([{ "uid": MINECRAFT_UID, "version": "1.21.1" }])),
        );

        assert_eq!(
            content_roots(&mc_folder, Some(&instances_dir), "pack"),
            [mc_folder.clone()]
        );
        assert_eq!(
            content_roots(&mc_folder, Some(&instances_dir), ""),
            [mc_folder.clone()]
        );

        apply_modpack_to_instance(
            &mc_folder,
            &instances_dir,
            "alpha",
            &local_modpack("pack", "1.21.1", ModLoader::Fabric),
            Some("0.16.9"),
        )
        .unwrap();
        assert_eq!(
            content_roots(&mc_folder, Some(&instances_dir), "pack"),
            [instances_dir.join("alpha").join("minecraft")]
        );

        crate::modpacks::apply_modpack(&mc_folder, "pack").unwrap();
        assert_eq!(
            content_roots(&mc_folder, Some(&instances_dir), "pack"),
            [
                mc_folder.clone(),
                instances_dir.join("alpha").join("minecraft"),
            ]
        );
        assert_eq!(content_roots(&mc_folder, None, "pack"), [mc_folder.clone()]);
        assert_eq!(
            content_roots(&mc_folder, Some(&instances_dir), "other"),
            [mc_folder]
        );
    }

    #[test]
    fn find_data_dir_prefers_an_existing_override() {
        let dir = tempdir().unwrap();
        let data_dir = dir.path().join("Prism");
        std::fs::create_dir_all(data_dir.join("instances")).unwrap();

        assert_eq!(find_data_dir(Some(data_dir.clone())), Some(data_dir));
        assert_eq!(find_data_dir(Some(dir.path().join("missing"))), None);
    }

    #[tokio::test]
    async fn resolve_loader_version_prefers_the_newest_recommended_build() {
        let _guard = PROVIDER_HTTP_TEST_MUTEX.lock().await;
        clear_provider_http_cache().await;

        let server = MockServer::start();
        unsafe {
            std::env::set_var("QUADRANT_TEST_PRISM_META_BASE", server.base_url());
        }

        let fabric = server.mock(|when, then| {
            when.method(GET).path("/v1/net.fabricmc.fabric-loader/index.json");
            then.status(200).json_body(json!({
                "versions": [
                    { "version": "0.15.0", "recommended": true, "releaseTime": "2024-01-01T00:00:00+00:00" },
                    { "version": "0.16.9", "recommended": true, "releaseTime": "2024-09-01T00:00:00+00:00" },
                    { "version": "0.17.0-beta", "recommended": false, "releaseTime": "2025-01-01T00:00:00+00:00" }
                ]
            }));
        });
        let forge = server.mock(|when, then| {
            when.method(GET).path("/v1/net.minecraftforge/index.json");
            then.status(200).json_body(json!({
                "versions": [
                    {
                        "version": "47.2.0",
                        "recommended": true,
                        "releaseTime": "2023-06-01T00:00:00+00:00",
                        "requires": [{ "uid": MINECRAFT_UID, "equals": "1.20.1" }]
                    },
                    {
                        "version": "47.4.0",
                        "recommended": false,
                        "releaseTime": "2024-06-01T00:00:00+00:00",
                        "requires": [{ "uid": MINECRAFT_UID, "equals": "1.20.1" }]
                    },
                    {
                        "version": "52.0.2",
                        "recommended": true,
                        "releaseTime": "2024-08-01T00:00:00+00:00",
                        "requires": [{ "uid": MINECRAFT_UID, "equals": "1.21.1" }]
                    }
                ]
            }));
        });
        // NeoForge marks nothing as recommended, and dates its builds with
        // fractional seconds and non-UTC offsets in an order that does not match
        // the array order.
        let neoforge = server.mock(|when, then| {
            when.method(GET).path("/v1/net.neoforged/index.json");
            then.status(200).json_body(json!({
                "versions": [
                    {
                        "version": "21.1.251",
                        "releaseTime": "2026-09-18T16:17:21.691325+00:00",
                        "requires": [{ "uid": MINECRAFT_UID, "equals": "1.21.1" }]
                    },
                    {
                        "version": "21.1.300",
                        "releaseTime": "2026-09-18T19:00:00+02:00",
                        "requires": [{ "uid": MINECRAFT_UID, "equals": "1.21.1" }]
                    },
                    {
                        "version": "21.1.999",
                        "releaseTime": "not a timestamp",
                        "requires": [{ "uid": MINECRAFT_UID, "equals": "1.21.1" }]
                    }
                ]
            }));
        });

        assert_eq!(
            resolve_loader_version(ModLoader::Fabric, "1.21.1")
                .await
                .unwrap(),
            "0.16.9"
        );
        // The recommended build for 1.20.1 wins over a newer unrecommended one.
        assert_eq!(
            resolve_loader_version(ModLoader::Forge, "1.20.1")
                .await
                .unwrap(),
            "47.2.0"
        );
        // 19:00+02:00 is 17:00 UTC, so it beats the 16:17 UTC build.
        assert_eq!(
            resolve_loader_version(ModLoader::NeoForge, "1.21.1")
                .await
                .unwrap(),
            "21.1.300"
        );
        assert!(
            resolve_loader_version(ModLoader::Forge, "1.7.10")
                .await
                .unwrap_err()
                .to_string()
                .contains("errorPrismLoaderVersionNotFound")
        );
        assert!(
            resolve_loader_version(ModLoader::Babric, "1.21.1")
                .await
                .unwrap_err()
                .to_string()
                .contains("errorPrismLoaderVersionNotFound")
        );

        fabric.assert_calls(1);
        forge.assert_calls(2);
        neoforge.assert_calls(1);

        unsafe {
            std::env::remove_var("QUADRANT_TEST_PRISM_META_BASE");
        }
        clear_provider_http_cache().await;
    }
}
