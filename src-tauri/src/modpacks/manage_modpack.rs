use std::{io::Write, path::Path};

use anyhow::anyhow;
use tauri::AppHandle;
use tauri_plugin_store::StoreExt;

use super::general::{get_modpacks, InstalledModpack, ModLoader};

#[tauri::command]
pub async fn delete_mod(
    modpack_name: String,
    mod_id: String,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    let modpacks = get_modpacks(false, app.clone()).await;
    let mut modpack = match modpacks.iter().find(|m| m.name == modpack_name) {
        Some(modpack) => modpack,
        None => {
            return Err(anyhow!("No modpack found").into());
        }
    }
    .to_owned();
    let config = app.store("config.json").unwrap();
    let binding = config.get("mcFolder").unwrap();
    let mc_folder = binding.as_str().unwrap();
    let mc_folder = Path::new(&mc_folder);
    let modpacks_folder = mc_folder.join("modpacks");
    let modpack_folder = modpacks_folder.join(modpack_name);
    let mut mods = modpack.mods;
    let to_delete_ids: Vec<_> = mods
        .iter()
        .filter(|m| m.id == mod_id)
        .map(|m| m.id.clone())
        .collect();
    if to_delete_ids.is_empty() {
        return Err(anyhow!("No mods found").into());
    }
    let to_delete_paths: Vec<_> = mods
        .iter()
        .filter(|m| m.id == mod_id)
        .map(|m| {
            let url = urlencoding::decode(m.download_url.clone().split("/").last().unwrap_or(""))
                .map_err(anyhow::Error::from)
                .unwrap_or_default()
                .into_owned();
            log::info!("File to delete: {}", &url);
            modpack_folder.join(url)
        })
        .collect();
    mods.retain(|m| !to_delete_ids.contains(&m.id));

    modpack.mods = mods;

    let mod_config = modpack_folder.join("modConfig.json");

    for file in to_delete_paths {
        std::fs::remove_file(file)?
    }
    std::fs::write(
        mod_config,
        serde_json::to_string_pretty(&InstalledModpack::from(modpack.clone()))?,
    )?;

    #[cfg(feature = "quadrant_id")]
    {
        let auto_sync = config.get("autoQuadrantSync").unwrap();

        let auto_sync: bool = auto_sync.as_bool().unwrap_or_default();

        if modpack.last_synced != 0 && auto_sync {
            use crate::account::quadrant_sync::sync_modpack;
            sync_modpack(modpack, true, app.clone()).await?;
        }
    }
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
    let mut modpack = match modpacks.iter().find(|m| m.name == modpack_source) {
        Some(modpack) => modpack,
        None => {
            return Err(anyhow!("No modpack found").into());
        }
    }
    .to_owned();
    let config = app.store("config.json").unwrap();
    let binding = config.get("mcFolder").unwrap();
    let mc_folder = binding.as_str().unwrap();
    let mc_folder = Path::new(&mc_folder);
    let modpacks_folder = mc_folder.join("modpacks");
    let modpack_folder = modpacks_folder.join(modpack_source);

    if name.clone().is_some() {
        modpack.name = name.clone().unwrap();
    }
    if version.is_some() {
        modpack.version = version.unwrap();
    }
    if mod_loader.is_some() {
        modpack.mod_loader = mod_loader.unwrap();
    }

    let mod_config = modpack_folder.join("modConfig.json");

    std::fs::write(
        mod_config,
        serde_json::to_string_pretty(&InstalledModpack::from(modpack.clone()))?,
    )?;

    #[cfg(feature = "quadrant_id")]
    {
        let auto_sync = config.get("autoQuadrantSync").unwrap();

        let auto_sync: bool = auto_sync.as_bool().unwrap_or_default();

        if modpack.last_synced != 0 && auto_sync {
            use crate::account::quadrant_sync::sync_modpack;
            sync_modpack(modpack, true, app.clone()).await?;
        }
    }

    if name.is_some() {
        let new_modpack_folder = modpacks_folder.join(name.unwrap());
        std::fs::rename(&modpack_folder, &new_modpack_folder)?;
    }

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
    if modpacks.iter().any(|m| m.name == name) {
        return Err(anyhow!("Modpack exists").into());
    };
    let config = app.store("config.json").unwrap();
    let binding = config.get("mcFolder").unwrap();
    let mc_folder = binding.as_str().unwrap();
    let mc_folder = Path::new(&mc_folder);
    let modpacks_folder = mc_folder.join("modpacks");
    let modpack_folder = modpacks_folder.join(&name);

    std::fs::create_dir_all(&modpack_folder)?;

    let mod_config = modpack_folder.join("modConfig.json");

    let mut mod_config_file = std::fs::File::options()
        .read(true)
        .write(true)
        .create(true)
        .open(mod_config)?;

    let new_modpack = InstalledModpack {
        mod_loader,
        name,
        version,
        mods: Vec::new(),
    };

    mod_config_file.write_all(
        serde_json::to_string_pretty(&new_modpack)
            .map_err(tauri::Error::from)?
            .as_bytes(),
    )?;

    Ok(())
}

#[tauri::command]
pub async fn delete_modpack(name: String, app: AppHandle) -> Result<(), tauri::Error> {
    let modpacks = get_modpacks(false, app.clone()).await;
    let is_applied: bool;
    match modpacks.iter().find(|m| m.name == name) {
        Some(modpack) => is_applied = modpack.is_applied,
        None => return Err(anyhow!("Modpack doesn't exist").into()),
    };
    let config = app.store("config.json").unwrap();
    let binding = config.get("mcFolder").unwrap();
    let mc_folder = binding.as_str().unwrap();
    let mc_folder = Path::new(&mc_folder);
    let mods_folder = mc_folder.join("mods");

    if is_applied {
        std::fs::remove_dir_all(mods_folder)?;
    }

    let modpacks_folder = mc_folder.join("modpacks");
    std::fs::remove_dir_all(modpacks_folder.join(name))?;
    Ok(())
}

#[tauri::command]
pub async fn open_modpacks_folder(app: AppHandle) -> Result<(), tauri::Error> {
    let config = app.store("config.json").unwrap();
    let binding = config.get("mcFolder").unwrap();
    let mc_folder = binding.as_str().unwrap();
    let mc_folder = Path::new(&mc_folder);
    let modpacks_folder = mc_folder.join("modpacks");
    open::that_detached(modpacks_folder)?;
    Ok(())
}

#[tauri::command]
pub async fn register_mod(
    mod_: crate::mc_mod::InstalledMod,
    modpack: String,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    let config = app.store("config.json").unwrap();
    let binding = config.get("mcFolder").unwrap();
    let mc_folder = binding.as_str().unwrap();
    let mc_folder = Path::new(&mc_folder);
    let modpacks_folder = mc_folder.join("modpacks");
    let modpack_folder = modpacks_folder.join(&modpack);

    let mod_config = get_modpacks(false, app)
        .await
        .into_iter()
        .find(|m| m.name == modpack);
    if mod_config.is_none() {
        return Err(anyhow!("Modpack doesn't exist").into());
    }
    let mut mod_config = mod_config.unwrap();
    let mod_exists = mod_config
        .mods
        .clone()
        .into_iter()
        .find(|m| m.id == mod_.id);
    if mod_exists.is_some() {
        return Err(anyhow!("Mod already registered").into());
    }
    mod_config.mods.push(mod_);
    std::fs::write(
        modpack_folder.join("modConfig.json"),
        serde_json::to_string_pretty(&mod_config)?,
    )?;
    Ok(())
}
