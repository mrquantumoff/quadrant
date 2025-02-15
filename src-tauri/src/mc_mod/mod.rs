use std::path::PathBuf;

use cache::{add_cache_index, file_hash, get_cache_index};

#[cfg(feature = "curseforge")]
use curseforge::{
    download_mod_curseforge, get_latest_mod_version_curseforge, search_mods_curseforge, ModFile,
};
use futures::StreamExt;
use http_cache_reqwest::Cache;
use http_cache_reqwest::CacheMode;
use http_cache_reqwest::HttpCache;
use http_cache_reqwest::HttpCacheOptions;
use http_cache_reqwest::MokaManager;
use modrinth::{
    download_mod_modrinth, get_latest_mod_version_modrinth, search_mods_modrinth, ModrinthFile,
};
use reqwest_middleware::ClientBuilder;
use serde::{Deserialize, Serialize};
use serde_json::json;
use tauri::{AppHandle, Emitter};
use tauri_plugin_http::reqwest;
use tauri_plugin_store::JsonValue;
use tauri_plugin_store::StoreExt;

use crate::modpacks::general::InstalledModpack;
use crate::{
    config::get_mc_folder,
    modpacks::general::{get_modpacks, ModLoader},
};

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
        let value = value.to_lowercase();
        match value.as_str() {
            "shader" => ModType::ShaderPack,
            "mod" => ModType::Mod,
            "resourcepack" => ModType::ResourcePack,
            _ => ModType::Unknown,
        }
    }
}

impl ModType {
    pub fn curseforge_id(&self) -> i32 {
        match *self {
            ModType::Mod => 6,
            ModType::ResourcePack => 12,
            ModType::ShaderPack => 6552,
            ModType::Unknown => 999,
        }
    }
    pub fn from_curseforge_class(class_id: i64) -> Self {
        match class_id {
            6 => Self::Mod,
            12 => Self::ResourcePack,
            6552 => Self::ShaderPack,
            // If mod type unknown, default to a regular mod
            _ => Self::Unknown,
        }
    }
    pub fn to_string(&self) -> String {
        match *self {
            ModType::Mod => "mod".to_string(),
            ModType::ResourcePack => "resourcepack".to_string(),
            ModType::ShaderPack => "shader".to_string(),
            ModType::Unknown => "unknown".to_string(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ModSource {
    #[serde(rename = "ModSource.curseForge")]
    CurseForge,
    #[serde(rename = "ModSource.modRinth")]
    Modrinth,
    #[serde(rename = "ModSource.online")]
    Online,
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

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InstalledMod {
    pub id: String,
    pub source: ModSource,
    pub download_url: String,
}

pub fn get_user_agent() -> String {
    format!(
        "mrquantumoff/quadrant/v{} (mrquantumoff.dev) (QUADRANT NEXT)",
        tauri_plugin_os::version()
    )
    .to_string()
}

#[derive(Clone, Serialize, Deserialize)]
pub struct MinecraftVersion {
    pub version: String,
    pub version_type: String,
}

impl From<JsonValue> for MinecraftVersion {
    fn from(value: JsonValue) -> Self {
        let value = value.as_object().unwrap();
        let version = value.get("version").unwrap().as_str().unwrap().to_string();
        let version_type = value
            .get("version_type")
            .unwrap()
            .as_str()
            .unwrap()
            .to_string();
        Self {
            version,
            version_type,
        }
    }
}

impl From<MinecraftVersion> for JsonValue {
    fn from(value: MinecraftVersion) -> Self {
        let mut map = serde_json::Map::new();
        map.insert(
            "version".to_string(),
            serde_json::Value::String(value.version),
        );
        map.insert(
            "version_type".to_string(),
            serde_json::Value::String(value.version_type),
        );
        JsonValue::Object(map)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UniversalModFile {
    pub id: Option<String>,
    pub file_name: String,
    pub download_url: String,
    pub sha1: String,
    pub size: u64,
}

#[cfg(feature = "curseforge")]
impl From<ModFile> for UniversalModFile {
    fn from(value: ModFile) -> Self {
        Self {
            id: Some(value.id.to_string()),
            file_name: value.file_name,
            download_url: value.download_url,
            sha1: value
                .hashes
                .iter()
                .find(|hash| hash.algo == 1)
                .expect("failedToGetHash")
                .value
                .clone(),
            size: value.file_length,
        }
    }
}

impl From<ModrinthFile> for UniversalModFile {
    fn from(value: ModrinthFile) -> Self {
        Self {
            id: None,
            file_name: value.filename,
            download_url: value.url,
            sha1: value.hashes.sha1.clone(),
            size: value.size,
        }
    }
}

#[tauri::command]
pub async fn get_versions(_app: AppHandle) -> Result<Vec<MinecraftVersion>, tauri::Error> {
    let uri = "https://api.modrinth.com/v2/tag/game_version";

    let client = ClientBuilder::new(reqwest::Client::new())
        .with(Cache(HttpCache {
            mode: CacheMode::Default,
            options: HttpCacheOptions::default(),
            manager: MokaManager::default(),
        }))
        .build();
    let res = client
        .get(uri)
        .header("User-Agent", get_user_agent())
        .send()
        .await
        .map_err(anyhow::Error::from)?;
    let body: Vec<MinecraftVersion> = res.json().await.map_err(anyhow::Error::from)?;
    let body: Vec<MinecraftVersion> = body
        .into_iter()
        .filter(|version| version.version_type == "release" && !version.version.is_empty())
        .collect();
    Ok(body)
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GlobalSearchModsArgs {
    source: ModSource,
    query: String,
    mod_type: String,
    filter_on: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct SearchModsArgs {
    query: String,
    mod_type: String,
    filter_on: bool,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GetModArgs {
    id: String,
    downloadable: bool,
    show_previous_version: bool,
    deletable: bool,
    version_target: String,
    mod_loader: ModLoader,
    modpack: String,
    selectable: bool,
    select_url: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct IdentifiedMod {
    pub installed_mod: InstalledMod,
    pub file_name: String,
}

#[tauri::command]
pub async fn check_mod_updates(
    mod_to_update: Mod,
    minecraft_version: String,
    mod_loader: ModLoader,
    modpack_name: String,
    app: AppHandle,
) -> Result<Option<Mod>, tauri::Error> {
    let mut new_mod = mod_to_update.clone();
    let modpack = get_modpacks(false, app.clone()).await;
    let modpack = modpack.iter().find(|m| m.name == modpack_name);
    if modpack.is_none() {
        return Err(anyhow::Error::msg("Modpack not found").into());
    }
    let modpack = modpack.unwrap().to_owned();
    let config = app
        .store("config.json")
        .map_err(|e| tauri::Error::from(anyhow::Error::from(e)))?;
    let show_unupgradeable_mods: bool = config
        .get("showUnupgradeableMods")
        .unwrap()
        .as_bool()
        .unwrap();

    let existing_mod = modpack.mods.iter().find(|m| m.id == mod_to_update.id);

    new_mod.show_previous_version = true;
    new_mod.deleteable = false;
    new_mod.autoinstallable = true;
    match mod_to_update.source {
        ModSource::CurseForge => {
            #[cfg(feature = "curseforge")]
            {
                let latest_file = get_latest_mod_version_curseforge(
                    mod_to_update.id,
                    minecraft_version,
                    mod_loader,
                    mod_to_update.mod_type,
                    None,
                )
                .await?;
                if latest_file.is_some() {
                    let latest_file = UniversalModFile::from(latest_file.unwrap());

                    new_mod.new_version = Some(latest_file);
                }
            }
            return Ok(None);
        }
        ModSource::Modrinth => {
            let latest_file = get_latest_mod_version_modrinth(
                mod_to_update.id,
                minecraft_version,
                mod_loader,
                mod_to_update.mod_type,
            )
            .await?;
            if latest_file.is_some() {
                let latest_file = UniversalModFile::from(latest_file.unwrap());
                new_mod.new_version = Some(latest_file);
            }
        }
        _ => {}
    }
    if existing_mod.is_some() && new_mod.new_version.is_some() {
        let existing_mod = existing_mod.unwrap();
        let new_file = new_mod.clone().new_version.unwrap();
        if existing_mod.download_url != new_file.download_url {
            new_mod.downloadable = true;
        }
        if existing_mod.download_url == new_file.download_url && !show_unupgradeable_mods {
            return Ok(None);
        }
    }
    Ok(Some(new_mod))
}

#[tauri::command]
pub async fn search_mods(
    args: GlobalSearchModsArgs,
    app: AppHandle,
) -> Result<Vec<Mod>, tauri::Error> {
    let mut mods: Vec<Mod> = Vec::new();

    let search_args = SearchModsArgs {
        query: args.query,
        mod_type: args.mod_type,
        filter_on: args.filter_on,
    };

    match args.source {
        ModSource::CurseForge => {
            #[cfg(feature = "curseforge")]
            {
                mods.append(&mut search_mods_curseforge(app, search_args).await?)
            }
        }

        ModSource::Modrinth => mods.append(&mut search_mods_modrinth(app, search_args).await?),
        _ => {}
    }

    mods.sort_by(|a, b| b.download_count.cmp(&a.download_count));
    Ok(mods)
}

pub fn get_mod_url(slug: String, mod_type: ModType, source: ModSource) -> String {
    let base_url = match source {
        ModSource::CurseForge => "https://curseforge.com/minecraft",
        ModSource::Modrinth => "https://modrinth.com",
        _ => "",
    };

    let mod_type = match source {
        ModSource::CurseForge => match mod_type {
            ModType::Mod => "mc-mods",
            ModType::ResourcePack => "texture-packs",
            ModType::ShaderPack => "customization",
            ModType::Unknown => "",
        },
        ModSource::Modrinth => &mod_type.to_string(),
        _ => "",
    };

    format!("{}/{}/{}", base_url, mod_type, slug).to_string()
}

#[tauri::command]
pub fn get_user_url(username: String, source: ModSource) -> String {
    let base_url = match source {
        ModSource::CurseForge => "https://curseforge.com/members",
        ModSource::Modrinth => "https://modrinth.com/user",
        _ => "",
    };

    format!("{}/{}", base_url, username).to_string()
}

#[tauri::command]
pub async fn install_mod(
    id: String,
    minecraft_version: String,
    mod_loader: ModLoader,
    source: ModSource,
    modpack: Option<String>,
    mod_type: ModType,
    #[allow(unused_variables)] // This is used in the CurseForge feature
    file_id: Option<String>,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    let download_path = match source {
        ModSource::CurseForge => {
            #[cfg(feature = "curseforge")]
            {
                download_mod_curseforge(
                    id.clone(),
                    minecraft_version,
                    mod_loader,
                    mod_type,
                    file_id,
                    app.clone(),
                )
                .await
                .inspect_err(|e| log::error!("Error downloading CurseForge mod: {}", e))
                .map_err(tauri::Error::from)?
            }
            #[cfg(not(feature = "curseforge"))]
            {
                return Err(anyhow::Error::msg("CurseForge is not enabled").into());
            }
        }

        ModSource::Modrinth => download_mod_modrinth(
            id.clone(),
            minecraft_version,
            mod_loader,
            mod_type,
            app.clone(),
        )
        .await
        .inspect_err(|e| log::error!("Error downloading Modrinth mod: {}", e))
        .map_err(tauri::Error::from)?,
        _ => {
            unimplemented!()
        }
    };
    app.emit(
        "modInstallProgress",
        json!({
            "modId": id,
            "progress": 0.5
        }),
    )?;

    install_local_file(
        download_path.0,
        download_path.1,
        mod_type,
        modpack,
        id.clone(),
        source,
        app.clone(),
    )
    .await?;

    app.emit(
        "modInstallProgress",
        json!({
            "modId": id,
            "progress": 1
        }),
    )?;
    Ok(())
}

pub async fn get_file(
    file: UniversalModFile,
    id: String,
    app: AppHandle,
) -> Result<(PathBuf, std::string::String), anyhow::Error> {
    // Check if the file is already cached
    let cached_file = get_cache_index(file.sha1.clone()).await?;
    if cached_file.is_some() {
        let cached_file = cached_file.unwrap();
        let cached_file = std::fs::read(cached_file.file_name)?;
        let file_path = add_cache_index(
            file.clone().file_name,
            cached_file.as_slice(),
            file.sha1.clone(),
        )
        .await?;
        app.emit(
            "modDownloadProgress",
            json!({
                "modId": id,
                "progress": 1
            }),
        )?;
        log::info!("File is cached");
        return Ok((file_path, file.download_url));
    }
    let client = reqwest::Client::new();
    let request = client
        .get(&file.download_url)
        .header("User-Agent", get_user_agent())
        .build()?;
    let mut body = client.execute(request).await?.bytes_stream();
    let mut file_bytes: Vec<u8> = Vec::new();
    let file_length = &file.size;
    while let Some(Ok(new_bytes)) = body.next().await {
        file_bytes.append(&mut new_bytes.to_vec());
        let progress = file_bytes.len() as u64 / file_length;
        app.emit(
            "modDownloadProgress",
            json!({
                "modId": id,
                "progress": progress
            }),
        )?;
    }
    app.emit(
        "modDownloadProgress",
        json!({
            "modId": id,
            "progress": 1
        }),
    )?;
    let hash = file_hash(file_bytes.as_slice());
    let file_path = add_cache_index(file.file_name.clone(), &file_bytes, hash).await?;

    Ok((file_path, file.clone().download_url))
}

pub async fn install_local_file(
    file: PathBuf,
    download_url: String,
    mod_type: ModType,
    modpack: Option<String>,
    id: String,
    source: ModSource,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    let local_mod = InstalledMod {
        id: id.clone(),
        source: source,
        download_url: download_url,
    };
    let target_path: PathBuf;

    match mod_type {
        ModType::Mod => {
            let modpack = modpack.expect("modpackRequired");
            // Store the modpacks in a local variable
            let modpacks = get_modpacks(false, app.clone()).await;

            // Use the local variable for iteration and borrowing
            let modpack = modpacks.iter().find(|m| m.name == modpack);
            if modpack.is_none() {
                return Err(anyhow::Error::msg("Modpack not found").into());
            }
            let mut modpack = modpack.unwrap().to_owned();
            // Remove the old version if it exists
            if modpack.mods.iter().any(|m| m.id == id) {
                modpack.mods.retain(|m| m.id != id);
            }
            modpack.mods.push(local_mod);

            let modpack_path = modpack.get_modpack_path(app.clone());

            std::fs::write(
                modpack_path.join("modConfig.json"),
                serde_json::to_string_pretty(&InstalledModpack::from(modpack.clone()))?,
            )?;

            #[cfg(feature = "quadrant_id")]
            {
                let config = app.store("config.json").map_err(|e| anyhow::anyhow!(e))?;
                let auto_sync = config.get("autoQuadrantSync").unwrap();

                let auto_sync: bool = auto_sync.as_bool().unwrap_or_default();

                if modpack.last_synced != 0 && auto_sync {
                    use crate::account::quadrant_sync::sync_modpack;
                    sync_modpack(modpack, true, app.clone()).await?;
                }
            }

            target_path = modpack_path.join(file.file_name().unwrap());
        }
        ModType::ResourcePack => {
            let modpack_path = get_mc_folder()?.unwrap().join("resourcepacks");
            target_path = modpack_path.join(file.file_name().unwrap());
        }
        ModType::ShaderPack => {
            let modpack_path = get_mc_folder()?.unwrap().join("shaderpacks");
            target_path = modpack_path.join(file.file_name().unwrap());
        }
        ModType::Unknown => {
            return Err(anyhow::Error::msg("unsupportedDownload").into());
        }
    }

    // Copy the file to the modpack folder
    std::fs::copy(file, target_path)?;
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
    let downloaded_file = get_file(file, id.clone(), app.clone()).await?;
    install_local_file(
        downloaded_file.0,
        downloaded_file.1,
        mod_type,
        modpack,
        id,
        source,
        app,
    )
    .await
}

#[tauri::command]
pub async fn identify_modpack(
    modpack: String,
    app: AppHandle,
) -> Result<Vec<IdentifiedMod>, tauri::Error> {
    let config = app.store("config.json").unwrap();
    let curseforge_enabled = config.get("curseforge").unwrap();
    let modrinth_enabled = config.get("modrinth").unwrap();
    let mut mods: Vec<IdentifiedMod> = Vec::new();
    if curseforge_enabled == true {
        #[cfg(feature = "curseforge")]
        {
            // let mut curse_mods = ;
            mods.append(
                &mut curseforge::identify_modpack_curseforge(modpack.clone(), app.clone()).await?,
            );
        }
    }
    if modrinth_enabled == true {
        mods.append(&mut modrinth::identify_modpack_modrinth(modpack, app).await?);
    }
    Ok(mods)
}
