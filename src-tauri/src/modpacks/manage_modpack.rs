use anyhow::anyhow;
use quadrant_core::ports::Shell;
use tauri::AppHandle;
use tauri_plugin_store::StoreExt;

use crate::tauri_adapter::{TauriShell, mc_folder};

use super::general::{ModLoader, get_modpacks};

#[tauri::command]
pub async fn delete_mod(
    modpack_name: String,
    mod_id: String,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    let modpacks = get_modpacks(false, app.clone()).await;
    let modpack = quadrant_core::modpacks::delete_mod(
        &mc_folder(&app).map_err(tauri::Error::from)?,
        &modpacks,
        &modpack_name,
        &mod_id,
    )
    .map_err(tauri::Error::from)?;

    #[cfg(feature = "quadrant_id")]
    maybe_auto_sync(&app, modpack).await?;

    Ok(())
}

#[tauri::command]
pub async fn update_modpack(
    modpack_source: String,
    name: Option<String>,
    version: Option<String>,
    mod_loader: Option<ModLoader>,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    let modpacks = get_modpacks(false, app.clone()).await;
    let modpack = quadrant_core::modpacks::update_modpack(
        &mc_folder(&app).map_err(tauri::Error::from)?,
        &modpacks,
        &modpack_source,
        name,
        version,
        mod_loader,
    )
    .map_err(tauri::Error::from)?;

    #[cfg(feature = "quadrant_id")]
    maybe_auto_sync(&app, modpack).await?;

    Ok(())
}

#[tauri::command]
pub async fn create_modpack(
    name: String,
    version: String,
    mod_loader: ModLoader,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    let modpacks = get_modpacks(false, app.clone()).await;
    quadrant_core::modpacks::create_modpack(
        &mc_folder(&app).map_err(tauri::Error::from)?,
        &modpacks,
        &name,
        &version,
        mod_loader,
    )
    .map_err(tauri::Error::from)
}

#[tauri::command]
pub async fn delete_modpack(name: String, app: AppHandle) -> Result<(), tauri::Error> {
    let modpacks = get_modpacks(false, app.clone()).await;
    quadrant_core::modpacks::delete_modpack(
        &mc_folder(&app).map_err(tauri::Error::from)?,
        &modpacks,
        &name,
    )
    .map_err(tauri::Error::from)
}

#[tauri::command]
pub async fn open_modpacks_folder(app: AppHandle) -> Result<(), tauri::Error> {
    let modpacks_path = mc_folder(&app)
        .map_err(tauri::Error::from)?
        .join("modpacks");
    TauriShell::new(app)
        .open_path(&modpacks_path)
        .map_err(tauri::Error::from)
}

#[tauri::command]
pub async fn register_mod(
    mod_: crate::mc_mod::InstalledMod,
    modpack: String,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    let modpacks = get_modpacks(false, app.clone()).await;
    quadrant_core::modpacks::register_mod(
        &mc_folder(&app).map_err(tauri::Error::from)?,
        &modpacks,
        mod_,
        &modpack,
    )
    .map_err(tauri::Error::from)
}

#[cfg(feature = "quadrant_id")]
async fn maybe_auto_sync(
    app: &AppHandle,
    modpack: quadrant_core::models::LocalModpack,
) -> Result<(), tauri::Error> {
    let config = app.store("config.json").map_err(anyhow::Error::from)?;
    let auto_sync = config
        .get("autoQuadrantSync")
        .ok_or_else(|| anyhow!("autoQuadrantSync is not configured"))?
        .as_bool()
        .unwrap_or_default();

    if modpack.last_synced != 0 && auto_sync {
        use crate::account::quadrant_sync::sync_modpack;
        sync_modpack(modpack, true, app.clone()).await?;
    }

    Ok(())
}
