use anyhow::anyhow;
use tauri::AppHandle;
use tauri_plugin_store::StoreExt;

pub use quadrant_core::mc_mod::{
    GetModArgs, GlobalSearchModsArgs, IdentifiedMod, MinecraftVersion, Mod, ModType,
    SearchModsArgs, UniversalModFile, get_mod_url, get_user_agent,
};
pub use quadrant_core::models::{InstalledMod, ModSource};

use crate::{
    modpacks::general::get_modpacks,
    tauri_adapter::{TauriEventSink, TauriSettingsStore, mc_folder},
};

#[cfg(feature = "curseforge")]
pub mod curseforge;
pub mod modrinth;

#[tauri::command]
pub async fn get_versions() -> Result<Vec<MinecraftVersion>, tauri::Error> {
    quadrant_core::mc_mod::get_versions()
        .await
        .map_err(tauri::Error::from)
}

#[tauri::command]
pub async fn check_mod_updates(
    mod_to_update: Mod,
    minecraft_version: String,
    mod_loader: quadrant_core::models::ModLoader,
    modpack_name: String,
    app: AppHandle,
) -> Result<Option<Mod>, tauri::Error> {
    let modpacks = get_modpacks(false, app.clone()).await;
    let modpack = modpacks
        .into_iter()
        .find(|modpack| modpack.name == modpack_name)
        .ok_or_else(|| tauri::Error::from(anyhow!("Modpack not found")))?;
    let config = app.store("config.json").map_err(anyhow::Error::from)?;
    let show_unupgradeable_mods = config
        .get("showUnupgradeableMods")
        .and_then(|value| value.as_bool())
        .unwrap_or(false);

    quadrant_core::mc_mod::check_mod_updates(
        mod_to_update,
        minecraft_version,
        mod_loader,
        modpack,
        show_unupgradeable_mods,
    )
    .await
    .map_err(tauri::Error::from)
}

#[tauri::command]
pub async fn search_mods(
    args: GlobalSearchModsArgs,
    app: AppHandle,
) -> Result<Vec<Mod>, tauri::Error> {
    quadrant_core::mc_mod::search_mods(args, &TauriSettingsStore::new(app, "config.json"))
        .await
        .map_err(tauri::Error::from)
}

#[tauri::command]
pub async fn install_mod(
    id: String,
    minecraft_version: String,
    mod_loader: quadrant_core::models::ModLoader,
    source: ModSource,
    modpack: Option<String>,
    mod_type: ModType,
    #[allow(unused_variables)] file_id: Option<String>,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    let existing_modpacks = get_modpacks(false, app.clone()).await;
    let updated_modpack = quadrant_core::mc_mod::install_mod(
        &mc_folder(&app).map_err(tauri::Error::from)?,
        &existing_modpacks,
        &TauriSettingsStore::new(app.clone(), "config.json"),
        &TauriEventSink::new(app.clone()),
        id,
        minecraft_version,
        mod_loader,
        source,
        modpack,
        mod_type,
        file_id,
    )
    .await
    .map_err(tauri::Error::from)?;

    maybe_auto_sync_updated_modpack(&app, updated_modpack).await?;
    Ok(())
}

#[tauri::command]
pub async fn install_remote_file(
    file: UniversalModFile,
    mod_type: ModType,
    modpack: Option<String>,
    source: ModSource,
    id: String,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    let existing_modpacks = get_modpacks(false, app.clone()).await;
    let updated_modpack = quadrant_core::mc_mod::install_remote_file(
        &mc_folder(&app).map_err(tauri::Error::from)?,
        &existing_modpacks,
        &TauriEventSink::new(app.clone()),
        file,
        mod_type,
        modpack,
        source,
        id,
    )
    .await
    .map_err(tauri::Error::from)?;

    maybe_auto_sync_updated_modpack(&app, updated_modpack).await?;
    Ok(())
}

#[tauri::command]
pub async fn identify_modpack(
    modpack: String,
    app: AppHandle,
) -> Result<Vec<IdentifiedMod>, tauri::Error> {
    let config = app.store("config.json").map_err(anyhow::Error::from)?;
    let curseforge_enabled = config
        .get("curseforge")
        .and_then(|value| value.as_bool())
        .unwrap_or(false);
    let modrinth_enabled = config
        .get("modrinth")
        .and_then(|value| value.as_bool())
        .unwrap_or(false);

    quadrant_core::mc_mod::identify_modpack(
        &mc_folder(&app).map_err(tauri::Error::from)?,
        modpack,
        curseforge_enabled,
        modrinth_enabled,
    )
    .await
    .map_err(tauri::Error::from)
}

#[tauri::command]
pub fn get_user_url(username: String, source: ModSource) -> String {
    quadrant_core::mc_mod::get_user_url(username, source)
}

#[cfg(feature = "quadrant_id")]
async fn maybe_auto_sync_updated_modpack(
    app: &AppHandle,
    updated_modpack: Option<quadrant_core::models::LocalModpack>,
) -> Result<(), tauri::Error> {
    let Some(modpack) = updated_modpack else {
        return Ok(());
    };

    let config = app.store("config.json").map_err(anyhow::Error::from)?;
    let auto_sync = config
        .get("autoQuadrantSync")
        .and_then(|value| value.as_bool())
        .unwrap_or(false);

    if modpack.last_synced != 0 && auto_sync {
        use crate::account::quadrant_sync::sync_modpack;
        sync_modpack(modpack, true, app.clone()).await?;
    }

    Ok(())
}

#[cfg(not(feature = "quadrant_id"))]
async fn maybe_auto_sync_updated_modpack(
    _app: &AppHandle,
    _updated_modpack: Option<quadrant_core::models::LocalModpack>,
) -> Result<(), tauri::Error> {
    Ok(())
}
