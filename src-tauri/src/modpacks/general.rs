use crate::mc_mod::{InstalledMod, ModSource};
use anyhow::anyhow;
use chrono::prelude::*;
use futures::StreamExt;
use log::error;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::{
    io::Write,
    path::{Path, PathBuf},
};
use tauri::{AppHandle, Emitter};
use tauri_plugin_http::reqwest;
use tauri_plugin_store::StoreExt;

#[derive(Serialize, Deserialize, Debug, Clone)]
pub enum ModLoader {
    #[serde(rename = "Forge")]
    Forge,
    #[serde(rename = "Fabric")]
    Fabric,
    #[serde(rename = "NeoForge")]
    NeoForge,
    #[serde(rename = "Quilt")]
    Quilt,
    #[serde(rename = "Rift")]
    Rift,
    #[serde(rename = "Unknown")]
    Unknown,
}

impl From<String> for ModLoader {
    fn from(value: String) -> Self {
        match value.to_lowercase().as_str() {
            "forge" => ModLoader::Forge,
            "fabric" => ModLoader::Fabric,
            "neoforge" => ModLoader::NeoForge,
            "quilt" => ModLoader::Quilt,
            "rift" => ModLoader::Rift,
            _ => ModLoader::Unknown,
        }
    }
}

impl ModLoader {
    pub fn to_string(&self) -> String {
        match self {
            ModLoader::Forge => "Forge".to_string(),
            ModLoader::Fabric => "Fabric".to_string(),
            ModLoader::NeoForge => "NeoForge".to_string(),
            ModLoader::Quilt => "Quilt".to_string(),
            ModLoader::Rift => "Rift".to_string(),
            ModLoader::Unknown => "Unknown".to_string(),
        }
    }
    pub fn to_curseforge_id(&self) -> i64 {
        match self {
            ModLoader::Forge => 1,
            ModLoader::Fabric => 4,
            ModLoader::NeoForge => 6,
            ModLoader::Rift => 999,
            ModLoader::Quilt => 5,
            ModLoader::Unknown => 0,
        }
    }
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]

pub struct InstalledModpack {
    pub name: String,
    pub version: String,
    pub mod_loader: ModLoader,
    pub mods: Vec<InstalledMod>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]

pub struct LocalModpack {
    pub name: String,
    pub version: String,
    pub mod_loader: ModLoader,
    pub mods: Vec<InstalledMod>,
    pub is_applied: bool,
    pub last_synced: i64,
}

impl From<LocalModpack> for InstalledModpack {
    fn from(modpack: LocalModpack) -> Self {
        InstalledModpack {
            name: modpack.name,
            version: modpack.version,
            mod_loader: modpack.mod_loader,
            mods: modpack.mods,
        }
    }
}

impl LocalModpack {
    pub fn get_modpack_path(&self, app: AppHandle) -> PathBuf {
        let config = app.store("config.json").unwrap();
        let binding = config.get("mcFolder").unwrap();
        let mc_folder = binding.as_str().unwrap();
        let mc_folder = Path::new(&mc_folder);

        mc_folder.join("modpacks").join(&self.name)
    }
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct SyncInfo {
    pub last_synced: i64,
}

impl From<(InstalledModpack, bool, i64)> for LocalModpack {
    fn from(modpack: (InstalledModpack, bool, i64)) -> Self {
        LocalModpack {
            name: modpack.0.name,
            version: modpack.0.version,
            mod_loader: modpack.0.mod_loader,
            mods: modpack.0.mods,
            is_applied: modpack.1,
            last_synced: modpack.2,
        }
    }
}

#[tauri::command]
pub async fn get_modpacks(hide_free: bool, app: AppHandle) -> Vec<LocalModpack> {
    let mut modpacks: Vec<LocalModpack> = Vec::new();
    let config = app.store("config.json").unwrap();
    let binding = config.get("mcFolder").unwrap();
    let mc_folder = binding.as_str().unwrap();
    let mc_folder = Path::new(&mc_folder);
    let modpacks_folder = mc_folder.join("modpacks");
    if !modpacks_folder.exists() {
        error!("Modpacks folder doesn't exist!");
        return modpacks;
    }
    let mods_folder = mc_folder.join("mods");
    for entry in std::fs::read_dir(modpacks_folder).unwrap() {
        let entry = entry.unwrap();
        let path = entry.path();
        if path.is_dir() {
            let modpack_config = path.join("modConfig.json");
            let mut last_synced: i64 = 0;
            let modpack_sync = path.join("quadrantSync.json");

            let name = path.file_name().unwrap().to_str().unwrap().to_string();
            if hide_free && name == "free" {
                continue;
            }
            let mut is_applied = false;
            if mods_folder.is_symlink() {
                let mods_path = mods_folder.read_link().unwrap();
                if mods_path == path {
                    is_applied = true;
                }
            }
            if !modpack_config.exists() {
                modpacks.push(LocalModpack {
                    name,
                    version: "-".to_string(),
                    mods: Vec::new(),
                    mod_loader: ModLoader::Unknown,
                    is_applied,
                    last_synced,
                });
                continue;
            }
            let modpack_config = std::fs::File::open(modpack_config).unwrap();
            let reader = std::io::BufReader::new(modpack_config);
            if modpack_sync.exists() {
                let sync_info = std::fs::File::open(modpack_sync).unwrap();
                let reader = std::io::BufReader::new(sync_info);
                let sync_info: SyncInfo = serde_json::from_reader(reader).unwrap();
                last_synced = sync_info.last_synced * 1000;
            }
            let modpack: Result<InstalledModpack, serde_json::Error> =
                serde_json::from_reader(reader);
            if modpack.is_err() {
                modpacks.push(LocalModpack::from((
                    InstalledModpack {
                        mod_loader: ModLoader::Unknown,
                        name,
                        version: "1.12.2".to_string(), // Default to 1.12.2 if the modpack is corrupted
                        mods: Vec::new(),
                    },
                    is_applied,
                    last_synced,
                )));
                continue;
            }

            let mut modpack: InstalledModpack = modpack.unwrap();
            modpack.name = name;
            modpacks.push(LocalModpack::from((modpack, is_applied, last_synced)));
        }
    }
    modpacks
}

#[tauri::command]
pub fn frontend_apply_modpack(name: String, app: AppHandle) -> Result<(), tauri::Error> {
    apply_modpack(name, app).map_err(|e| e.into())
}

pub fn apply_modpack(name: String, app: AppHandle) -> Result<(), anyhow::Error> {
    let config = app.store("config.json")?;
    let binding = config.get("mcFolder").unwrap();
    let mc_folder = binding.as_str().unwrap();
    let modpackpath = PathBuf::from(&mc_folder).join("modpacks").join(name);
    let mods_path = PathBuf::from(&mc_folder).join("mods");
    if !modpackpath.exists() {
        return Err(anyhow::anyhow!("Modpack does not exist"));
    }
    if !mods_path.is_symlink() && mods_path.exists() {
        std::fs::rename(
            &mods_path,
            PathBuf::from(&mc_folder)
                .join("modpacks")
                .join(format!("mods backup from {}", Utc::now().to_rfc2822())),
        )?;
    }
    if mods_path.exists() {
        log::info!("Deleting mods folder");
        std::fs::remove_dir_all(&mods_path)?;
    }
    #[cfg(target_os = "windows")]
    {
        // std::os::windows::fs::
        std::os::windows::fs::symlink_dir(modpackpath, mods_path)?;
    }
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    {
        std::os::unix::fs::symlink(modpackpath, mods_path)?;
    }
    Ok(())
}

#[tauri::command]
pub async fn install_modpack(
    mod_config: InstalledModpack,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    let config = app.store("config.json").unwrap();
    let binding = config.get("mcFolder").unwrap();
    let mc_folder = binding.as_str().unwrap();
    let mc_folder = Path::new(&mc_folder);
    let modpacks_folder = mc_folder.join("modpacks");
    let modpack_folder = modpacks_folder.join(&mod_config.name);
    if !modpack_folder.exists() {
        std::fs::create_dir_all(&modpack_folder)?;
    }
    let mod_config_file = modpack_folder.join("modConfig.json");
    std::fs::write(&mod_config_file, serde_json::to_string_pretty(&mod_config)?)?;
    let mods = mod_config.mods;
    let total_mods = mods.len();
    let mut downloaded_mods = 0;
    let files = std::fs::read_dir(&modpack_folder)?;
    let mut file_names = Vec::new();

    // Check for existing files
    for mod_ in mods.clone() {
        let file_name =
            urlencoding::decode(&mod_.download_url.split("/").last().unwrap_or_default());
        file_names.push(file_name.map_err(|e| anyhow::anyhow!(e))?.to_string());
    }

    // Remove files that are not in the modpack
    for file in files {
        let file = file?;
        let file_name = file.file_name();
        if !file_names.contains(&file_name.to_string_lossy().to_string())
            && file_name != "modConfig.json"
        {
            std::fs::remove_file(file.path())?;
        }
    }

    // Download the missing files
    for mod_ in mods {
        let file_name = urlencoding::decode(
            mod_.download_url
                .clone()
                .split("/")
                .last()
                .unwrap_or_default(),
        )
        .map_err(|e| anyhow::anyhow!(e))?
        .to_string();
        let file = modpack_folder.join(file_name);
        if file.exists() {
            continue;
        }
        let mut file = std::fs::File::create(file)?;
        let response = reqwest::get(&mod_.download_url)
            .await
            .map_err(|e| anyhow::anyhow!(e))?;
        let mut bytes = response.bytes_stream();
        while let Some(item) = bytes.next().await {
            file.write_all(&item.map_err(|e| anyhow::anyhow!(e))?)?
        }
        downloaded_mods += 1;
        log::info!("Downloaded {} of {}", downloaded_mods, total_mods);

        let store = app.store("config.json").map_err(|e| anyhow::anyhow!(e))?;

        match mod_.source {
            ModSource::CurseForge => {
                let previous_cursefoge_count = store.get("curseforgeUsage");
                if let Some(previous_curseforge_count) = previous_cursefoge_count {
                    let previous_curseforge_count: i64 =
                        previous_curseforge_count.as_i64().unwrap_or_default();
                    store.set("curseforgeUsage", previous_curseforge_count + 1);
                }
            }
            ModSource::Modrinth => {
                let previous_cursefoge_count = store.get("modrinthUsage");
                if let Some(previous_modrinth_count) = previous_cursefoge_count {
                    let previous_modrinth_count: i64 =
                        previous_modrinth_count.as_i64().unwrap_or_default();
                    store.set("modrinthUsage", previous_modrinth_count + 1);
                }
            }
            _ => {}
        }
        app.emit(
            "modpackDownloadProgress",
            downloaded_mods as f64 / total_mods as f64,
        )?;
    }
    app.emit("modpackDownloadProgress", 1.0)?;
    Ok(())
}

#[tauri::command]
pub async fn set_modpack_sync_date(
    time: u64,
    modpack: String,
    app: tauri::AppHandle,
) -> Result<(), tauri::Error> {
    let mc_folder = app
        .store("config.json")
        .map_err(|e| anyhow!(e))?
        .get("mcFolder");
    let mc_folder = PathBuf::from(mc_folder.unwrap().as_str().unwrap());
    let modpack_folder = mc_folder.join("modpacks").join(modpack);
    let sync_file = modpack_folder.join("quadrantSync.json");

    std::fs::write(
        sync_file,
        serde_json::to_string_pretty(&json!({"last_synced": time}))?,
    )?;

    Ok(())
}
