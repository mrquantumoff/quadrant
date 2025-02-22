pub const BASE_URL: &str = "https://api.curseforge.com/";
pub const MINECRAFT_ID: i32 = 432;
use std::path::PathBuf;

use sha1::Digest;
use tauri::AppHandle;
use tauri_plugin_http::reqwest;
use tauri_plugin_store::StoreExt;

use crate::{
    mc_mod::{curseforge_fingerprint::*, get_user_agent, IdentifiedMod, InstalledMod},
    modpacks::general::{get_modpacks, LocalModpack, ModLoader},
};

use super::{get_file, get_mod_url, GetModArgs, Mod, ModSource, ModType, SearchModsArgs};

use chrono::prelude::*;
use serde::{Deserialize, Serialize};

use http_cache_reqwest::{Cache, CacheMode, HttpCache, HttpCacheOptions, MokaManager};
use reqwest_middleware::ClientBuilder;

#[derive(Serialize, Clone, Deserialize, Debug)]
pub struct ModFilesResponse {
    data: Vec<ModFile>,
}

#[derive(Serialize, Clone, Deserialize, Debug)]
pub struct ModFileResponse {
    data: ModFile,
}

#[derive(Serialize, Clone, Deserialize, Debug)]
pub struct ExactMatchesResponse {
    data: ExactMatches,
}

#[derive(Serialize, Clone, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct ModFile {
    pub id: u64,
    pub game_id: u64,
    pub mod_id: u64,
    pub is_available: bool,
    pub file_name: String,
    pub hashes: Vec<Hash>,
    pub file_date: String,
    pub file_length: u64,
    pub download_url: String,
}

#[derive(Serialize, Clone, Deserialize, Debug)]
pub struct Hash {
    pub value: String,
    pub algo: u8,
}

#[derive(Serialize, Clone, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct SortableGameVersion {
    pub game_version_name: String,
    pub game_version_padded: String,
    pub game_version: String,
    pub game_version_release_date: String,
    pub game_version_type_id: u8,
}

#[derive(Serialize, Clone, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Dependency {
    pub mod_id: u64,
    pub relation_type: u8,
}

#[derive(Serialize, Clone, Deserialize, Debug)]
pub struct Module {
    pub name: String,
    pub fingerprint: u64,
}

#[derive(Serialize, Clone, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct ExactMatches {
    pub exact_matches: Vec<ExactMatch>,
}

#[derive(Serialize, Clone, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct ExactMatch {
    pub file: ModFile,
}

#[tauri::command]
pub async fn get_mod_curseforge(args: GetModArgs) -> Result<Mod, tauri::Error> {
    let curseforge_token = env!("ETERNAL_API_TOKEN");

    let url = format!("{}v1/mods/{}", BASE_URL, args.id);

    let client = ClientBuilder::new(reqwest::Client::new())
        .with(Cache(HttpCache {
            mode: CacheMode::Default,
            options: HttpCacheOptions::default(),
            manager: MokaManager::default(),
        }))
        .build();
    let request = client
        .get(&url)
        .header("X-API-Key", curseforge_token)
        .header("User-Agent", get_user_agent())
        .build()
        .unwrap();
    let res = client.execute(request).await.map_err(anyhow::Error::from)?;
    let res_text = res.text().await.unwrap();

    let res_json: serde_json::Value =
        serde_json::from_str(&res_text).map_err(anyhow::Error::from)?;
    let res_data = &res_json["data"];

    let mod_class_id = res_data["classId"].as_i64().unwrap_or_default();
    let mod_class = ModType::from_curseforge_class(mod_class_id);

    let screenshots: Vec<String> = res_data["screenshots"]
        .as_array()
        .unwrap_or(&vec![])
        .iter()
        .map(|screenshot| {
            screenshot["thumbnailUrl"]
                .as_str()
                .unwrap_or_default()
                .to_string()
        })
        .collect();

    let logo = res_data["logo"]["url"]
        .as_str()
        .unwrap_or(
            "https://raw.githubusercontent.com/mrquantumoff/quadrant/next/public/logonobg.png",
        )
        .to_string();
    let final_mod = Mod {
        id: args.id,
        name: res_data["name"].as_str().unwrap_or_default().to_string(),
        description: res_data["summary"].as_str().unwrap_or_default().to_string(),
        download_count: res_data["downloadCount"].as_i64().unwrap_or_default(),
        version: res_data["dateModified"]
            .as_str()
            .unwrap_or_default()
            .to_string(),
        mod_type: mod_class,
        source: ModSource::CurseForge,
        slug: res_data["slug"].as_str().unwrap_or_default().to_string(),
        thumbnail_urls: screenshots,
        url: res_data["links"]["websiteUrl"]
            .as_str()
            .unwrap_or_default()
            .to_string(),
        license: "Unknown".to_string(),
        mod_icon_url: logo,
        downloadable: args.downloadable,
        show_previous_version: args.show_previous_version,
        new_version: None,
        deleteable: args.deletable,
        autoinstallable: false,
        selectable: args.selectable,
        select_url: args.select_url,
        modpack: Some(args.modpack),
    };
    Ok(final_mod)
}

#[tauri::command]
pub async fn get_mod_owners_curseforge(id: String) -> Result<Vec<String>, tauri::Error> {
    let curseforge_token = env!("ETERNAL_API_TOKEN");

    let url = format!("{}v1/mods/{}", BASE_URL, id);

    let client = reqwest::Client::new();
    let request = client
        .get(&url)
        .header("X-API-Key", curseforge_token)
        .header("User-Agent", get_user_agent())
        .build()
        .unwrap();
    let res = client.execute(request).await.map_err(anyhow::Error::from)?;
    let res_text = res.text().await.unwrap();

    let res_json: serde_json::Value =
        serde_json::from_str(&res_text).map_err(anyhow::Error::from)?;
    let res_data = &res_json["data"];
    let mut owners = Vec::new();
    if let Some(owners_data) = res_data["authors"].as_array() {
        for owner in owners_data {
            if let Some(username) = owner["name"].as_str() {
                owners.push(username.to_string());
            }
        }
    }
    Ok(owners)
}

#[tauri::command]
pub async fn get_mod_deps_curseforge(id: String) -> Result<Vec<Mod>, tauri::Error> {
    let curseforge_token = env!("ETERNAL_API_TOKEN");
    let url = format!("{}v1/mods/{}", BASE_URL, id);

    let client = reqwest::Client::new();
    let request = client
        .get(&url)
        .header("X-API-Key", curseforge_token)
        .header("User-Agent", get_user_agent())
        .build()
        .unwrap();

    let res = client.execute(request).await.map_err(anyhow::Error::from)?;
    let res_text = res.text().await.unwrap();
    let res_json: serde_json::Value =
        serde_json::from_str(&res_text).map_err(anyhow::Error::from)?;
    let res_data = &res_json["data"];

    let mods_to_get: Vec<String> = res_data["latestFileIndexes"][0]["dependencies"]
        .as_array()
        .unwrap_or(&vec![])
        .iter()
        .filter_map(|mod_info| {
            if let (Some(mod_info_id), Some(relation_type)) =
                (mod_info["id"].as_str(), mod_info["relationType"].as_i64())
            {
                if relation_type == 3 {
                    return Some(mod_info_id.to_string());
                }
            }
            None
        })
        .collect();

    let mut mods = Vec::new();
    for mod_to_get in mods_to_get {
        mods.push(
            get_mod_curseforge(GetModArgs {
                id: mod_to_get,
                show_previous_version: false,
                downloadable: true,
                deletable: false,
                mod_loader: ModLoader::Unknown,
                version_target: String::new(),
                modpack: String::new(),
                selectable: false,
                select_url: None,
            })
            .await?,
        );
    }

    Ok(mods)
}

#[tauri::command]
pub async fn search_mods_curseforge(
    app: AppHandle,
    args: SearchModsArgs,
) -> Result<Vec<Mod>, tauri::Error> {
    let mut mods: Vec<Mod> = Vec::new();
    let mod_type = ModType::from(args.mod_type);
    let mut raw_uri = format!(
        "{}v1/mods/search?gameId={}&searchFilter={}&sortOrder=desc&classId={}",
        crate::mc_mod::curseforge::BASE_URL,
        crate::mc_mod::curseforge::MINECRAFT_ID,
        args.query,
        mod_type.curseforge_id()
    );

    // if mod_type == ModType::ShaderPack {
    //     raw_uri = format!("{}&categoryId=4547", raw_uri);
    // }

    let config = app.store("config.json").map_err(anyhow::Error::from)?;

    if args.filter_on {
        let game_version: String = config
            .get("lastUsedVersion")
            .unwrap_or_default()
            .to_string()
            .replace("\"", "");
        // Remove the last part of the version
        let game_version = game_version.split('.').collect::<Vec<&str>>();
        let game_version = format!("{}.{}", game_version[0], game_version[1]);
        raw_uri = format!("{}&gameVersion={}", raw_uri, game_version);
    }
    if args.filter_on && mod_type == ModType::Mod {
        let mod_loader_type = ModLoader::from(
            config
                .get("lastUsedAPI")
                .unwrap_or_default()
                .to_string()
                .replace("\"", ""),
        );
        raw_uri = format!(
            "{}&modLoaderType={}",
            raw_uri,
            mod_loader_type.to_curseforge_id()
        );
    }
    let token = env!("ETERNAL_API_TOKEN");

    // log::info!("CurseForge Raw URI: {}", raw_uri);

    let client = reqwest::Client::new();
    let request = client
        .get(&raw_uri)
        .header("User-Agent", crate::mc_mod::get_user_agent())
        .header("X-API-Key", token)
        .build()
        .unwrap();
    let res = client.execute(request).await.map_err(anyhow::Error::from)?;
    let response_json: serde_json::Value = res.json().await.map_err(anyhow::Error::from)?;

    if let Some(data) = response_json["data"].as_array() {
        for mod_data in data {
            let mod_item = Mod {
                id: mod_data["id"].as_i64().unwrap_or_default().to_string(),
                name: mod_data["name"].as_str().unwrap_or_default().to_string(),
                description: mod_data["summary"].as_str().unwrap_or_default().to_string(),
                download_count: mod_data["downloadCount"].as_i64().unwrap_or_default(),
                version: mod_data["dateModified"]
                    .as_str()
                    .unwrap_or_default()
                    .to_string(),
                mod_type: ModType::from_curseforge_class(
                    mod_data["classId"].as_i64().unwrap_or_default(),
                ),
                source: ModSource::CurseForge,
                slug: mod_data["slug"].as_str().unwrap_or_default().to_string(),
                thumbnail_urls: mod_data["screenshots"]
                    .as_array()
                    .unwrap_or(&vec![])
                    .iter()
                    .map(|screenshot| {
                        screenshot["thumbnailUrl"]
                            .as_str()
                            .unwrap_or_default()
                            .to_string()
                    })
                    .collect(),
                url: get_mod_url(
                    mod_data["slug"].as_str().unwrap_or_default().to_string(),
                    ModType::from_curseforge_class(
                        mod_data["classId"].as_i64().unwrap_or_default(),
                    ),
                    ModSource::CurseForge,
                ),
                license: "Unknown".to_string(),
                mod_icon_url: mod_data["logo"]["url"]
                    .as_str()
                    .unwrap_or_default()
                    .to_string(),
                downloadable: true,
                show_previous_version: false,
                new_version: None,
                deleteable: false,
                autoinstallable: args.filter_on,
                selectable: false,
                select_url: None,
                modpack: None,
            };
            mods.push(mod_item);
        }
    }
    Ok(mods)
}

pub async fn get_latest_mod_version_curseforge(
    id: String,
    minecraft_version: String,
    mod_loader: ModLoader,
    mod_type: ModType,
    file_id: Option<String>,
) -> Result<Option<ModFile>, anyhow::Error> {
    let curseforge_token = env!("ETERNAL_API_TOKEN");
    // Get the mod file from the curseforge API
    let mut url = format!("{}v1/mods/{}/files", BASE_URL, id);
    let mut query = vec![("gameVersion", minecraft_version)];
    if mod_type == ModType::Mod {
        query.push(("modLoaderType", mod_loader.to_curseforge_id().to_string()));
    }
    if let Some(file_id) = file_id.clone() {
        url = format!("{}/{}", url, file_id);
    }
    let client = reqwest::Client::new();
    let response = client
        .get(&url)
        .header("X-API-Key", curseforge_token)
        .header("User-Agent", get_user_agent());
    let response = if file_id.is_some() {
        response
    } else {
        response.query(query.as_slice())
    };
    log::info!("Mod URL: {}", url);
    let response = response.send().await?;

    log::info!("Decoding mod download response");
    let last_file: Option<ModFile> = match file_id.is_some() {
        false => {
            log::info!("Getting mod files from other params");
            let json: ModFilesResponse = response.json().await?;
            let mut data: Vec<ModFile> = json.data;

            if data.is_empty() {
                return Err(anyhow::anyhow!("noVersion"));
            }

            data.sort_by(|a, b| {
                let date_a = DateTime::parse_from_rfc3339(&a.file_date).unwrap();
                let date_b = DateTime::parse_from_rfc3339(&b.file_date).unwrap();
                date_b.cmp(&date_a)
            });

            data.get(0).cloned()
        }
        true => {
            log::info!("Getting mod files from file id {}", file_id.unwrap());
            let json: ModFileResponse = response.json().await?;
            Some(json.data)
        }
    };
    Ok(last_file)
}

pub async fn download_mod_curseforge(
    id: String,
    minecraft_version: String,
    mod_loader: ModLoader,
    mod_type: ModType,
    file_id: Option<String>,
    app: AppHandle,
) -> Result<(PathBuf, String), anyhow::Error> {
    let file = get_latest_mod_version_curseforge(
        id.clone(),
        minecraft_version,
        mod_loader,
        mod_type,
        file_id,
    )
    .await?;
    if file.is_none() {
        return Err(anyhow::Error::msg("noVersion"));
    }
    let file = file.unwrap();
    let store = app.store("config.json").unwrap();
    store.set(
        "curseforgeUsage",
        store
            .get("curseforgeUsage")
            .unwrap()
            .as_i64()
            .unwrap_or_else(|| 0)
            + 1,
    );

    get_file(file.into(), id, app).await
}

pub async fn identify_modpack_curseforge(
    modpack: String,
    app: AppHandle,
) -> Result<Vec<IdentifiedMod>, anyhow::Error> {
    let mc_folder = app.store("config.json").unwrap().get("mcFolder");
    let mc_folder = PathBuf::from(mc_folder.unwrap().as_str().unwrap());
    let modpacks_folder = mc_folder.join("modpacks");
    let modpack_folder = modpacks_folder.join(&modpack);

    let existing_modpack: Vec<LocalModpack> = get_modpacks(false, app.clone())
        .await
        .into_iter()
        .filter(|m| &m.name == &modpack)
        .collect();
    if existing_modpack.is_empty() {
        return Err(anyhow::anyhow!("Modpack doesn't exist"));
    }
    let existing_modpack = existing_modpack.first().unwrap();
    let existing_files: Vec<String> = existing_modpack
        .mods
        .iter()
        .map(|m| {
            urlencoding::decode(&m.download_url)
                .unwrap_or_default()
                .to_string()
                .split("/")
                .last()
                .unwrap_or_default()
                .to_string()
        })
        .collect();
    let unknown_files: Vec<String> = std::fs::read_dir(&modpack_folder)?
        .filter(|file| match file {
            Ok(file) => {
                let file_name = file.file_name().to_string_lossy().to_string();
                !existing_files.contains(&file_name) && file_name.ends_with(".jar")
            }
            Err(_) => false,
        })
        .map(|f| f.unwrap().file_name().to_string_lossy().to_string())
        .collect();

    let mut mods: Vec<IdentifiedMod> = Vec::new();

    let mut hashes: Vec<(u32, String, String)> = Vec::new();

    for file in unknown_files {
        let file = modpack_folder.join(file);
        let contents = get_jar_contents(&file.to_string_lossy().to_string());
        let hash = compute_hash(&contents);
        // Calculate SHA1 hash
        let mut hasher = sha1::Sha1::new();
        hasher.update(contents);
        let hex_hash = hasher.finalize();
        let sha1 = hex::encode(hex_hash);
        hashes.push((
            hash,
            sha1,
            file.file_name().unwrap().to_string_lossy().to_string(),
        ));
    }
    let file_url = format!("{}v1/fingerprints/{}", BASE_URL, MINECRAFT_ID);

    let body = serde_json::json!({
        "fingerprints": hashes.iter().map(|hash| hash.0).collect::<Vec<u32>>(),
    });

    let client = reqwest::Client::new();
    let request = client
        .post(file_url)
        .header("User-Agent", get_user_agent())
        .header("X-API-Key", env!("ETERNAL_API_TOKEN"))
        .json(&body)
        .build()
        .unwrap();
    let res = client.execute(request).await?;

    let res_json: ExactMatchesResponse = res.json().await?;
    let matches = res_json.data.exact_matches;
    for match_ in matches {
        let file = match_.file;
        let hash = file.hashes.iter().find(|hash| hash.algo == 1);

        let original_file = hashes
            .iter()
            .find(|(_, sha1, _)| sha1 == &hash.unwrap().value)
            .map(|hash_info| hash_info.2.clone())
            .unwrap();

        mods.push(IdentifiedMod {
            installed_mod: InstalledMod {
                download_url: file.download_url,
                id: file.mod_id.to_string(),
                source: ModSource::CurseForge,
            },
            file_name: original_file,
        });
    }
    Ok(mods)
}
