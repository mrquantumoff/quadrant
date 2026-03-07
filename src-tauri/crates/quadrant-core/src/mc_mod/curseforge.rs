pub const BASE_URL: &str = "https://api.curseforge.com/";
pub const MINECRAFT_ID: i32 = 432;

use std::path::PathBuf;

use chrono::prelude::*;
use serde::{Deserialize, Serialize};
use sha1::Digest;

use crate::{
    Result,
    models::{InstalledMod, LocalModpack, ModLoader, ModSource},
    modpacks::get_modpacks,
    ports::{EventSink, SettingsStore},
};

use super::{
    GetModArgs, IdentifiedMod, Mod, ModType, SearchModsArgs, UniversalModFile, get_file,
    get_mod_url, get_user_agent,
};
use crate::mc_mod::curseforge_fingerprint::*;

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

#[derive(Serialize, Clone, Deserialize, Debug)]
pub struct Hash {
    pub value: String,
    pub algo: u8,
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

pub async fn get_mod_curseforge(args: GetModArgs) -> Result<Mod> {
    let res_json: serde_json::Value = reqwest::Client::new()
        .get(format!("{}v1/mods/{}", BASE_URL, args.id))
        .header("X-API-Key", env!("ETERNAL_API_TOKEN"))
        .header("User-Agent", get_user_agent())
        .send()
        .await?
        .json()
        .await?;
    let res_data = &res_json["data"];
    let mod_class =
        ModType::from_curseforge_class(res_data["classId"].as_i64().unwrap_or_default());
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
    Ok(Mod {
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
    })
}

pub async fn get_mod_owners_curseforge(id: String) -> Result<Vec<String>> {
    let res_json: serde_json::Value = reqwest::Client::new()
        .get(format!("{}v1/mods/{}", BASE_URL, id))
        .header("X-API-Key", env!("ETERNAL_API_TOKEN"))
        .header("User-Agent", get_user_agent())
        .send()
        .await?
        .json()
        .await?;
    let mut owners = Vec::new();
    if let Some(authors) = res_json["data"]["authors"].as_array() {
        for author in authors {
            if let Some(username) = author["name"].as_str() {
                owners.push(username.to_string());
            }
        }
    }
    Ok(owners)
}

pub async fn get_mod_deps_curseforge(id: String) -> Result<Vec<Mod>> {
    let res_json: serde_json::Value = reqwest::Client::new()
        .get(format!("{}v1/mods/{}", BASE_URL, id))
        .header("X-API-Key", env!("ETERNAL_API_TOKEN"))
        .header("User-Agent", get_user_agent())
        .send()
        .await?
        .json()
        .await?;
    let mods_to_get: Vec<String> = res_json["data"]["latestFileIndexes"][0]["dependencies"]
        .as_array()
        .unwrap_or(&vec![])
        .iter()
        .filter_map(|mod_info| {
            if let (Some(mod_info_id), Some(relation_type)) =
                (mod_info["id"].as_str(), mod_info["relationType"].as_i64())
                && relation_type == 3
            {
                return Some(mod_info_id.to_string());
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

pub async fn search_mods_curseforge(
    settings: &impl SettingsStore,
    args: SearchModsArgs,
) -> Result<Vec<Mod>> {
    let mod_type = ModType::from(args.mod_type);
    let mut raw_uri = format!(
        "{}v1/mods/search?gameId={}&searchFilter={}&sortOrder=desc&classId={}",
        BASE_URL,
        MINECRAFT_ID,
        args.query,
        mod_type.curseforge_id()
    );

    if args.filter_on {
        let mut game_version = settings.get_string("lastUsedVersion")?.unwrap_or_default();
        if mod_type != ModType::Mod {
            let trimmed_version = game_version.split('.').collect::<Vec<&str>>();
            if trimmed_version.len() >= 2 {
                game_version = format!("{}.{}", trimmed_version[0], trimmed_version[1]);
            }
        }
        raw_uri = format!("{}&gameVersion={}", raw_uri, game_version);
    }
    if args.filter_on && mod_type == ModType::Mod {
        let mod_loader_type =
            ModLoader::from(settings.get_string("lastUsedAPI")?.unwrap_or_default());
        raw_uri = format!(
            "{}&modLoaderType={}",
            raw_uri,
            mod_loader_type.to_curseforge_id()
        );
    }

    let response_json: serde_json::Value = reqwest::Client::new()
        .get(&raw_uri)
        .header("User-Agent", get_user_agent())
        .header("X-API-Key", env!("ETERNAL_API_TOKEN"))
        .send()
        .await?
        .json()
        .await?;

    let mut mods = Vec::new();
    if let Some(data) = response_json["data"].as_array() {
        for mod_data in data {
            mods.push(Mod {
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
            });
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
) -> Result<Option<ModFile>> {
    let mut url = format!("{}v1/mods/{}/files", BASE_URL, id);
    let mut query = vec![("gameVersion", minecraft_version)];
    if mod_type == ModType::Mod {
        query.push(("modLoaderType", mod_loader.to_curseforge_id().to_string()));
    }
    if let Some(file_id) = file_id.clone() {
        url = format!("{}/{}", url, file_id);
    }

    let request = reqwest::Client::new()
        .get(&url)
        .header("X-API-Key", env!("ETERNAL_API_TOKEN"))
        .header("User-Agent", get_user_agent());
    let response = if file_id.is_some() {
        request.send().await?
    } else {
        request.query(query.as_slice()).send().await?
    };

    Ok(if file_id.is_some() {
        Some(response.json::<ModFileResponse>().await?.data)
    } else {
        let mut data = response.json::<ModFilesResponse>().await?.data;
        if data.is_empty() {
            return Err(anyhow::anyhow!("noVersion"));
        }
        data.sort_by(|a, b| {
            let date_a = DateTime::parse_from_rfc3339(&a.file_date).unwrap();
            let date_b = DateTime::parse_from_rfc3339(&b.file_date).unwrap();
            date_b.cmp(&date_a)
        });
        data.first().cloned()
    })
}

pub async fn download_mod_curseforge(
    settings: &impl SettingsStore,
    event_sink: &impl EventSink,
    id: String,
    minecraft_version: String,
    mod_loader: ModLoader,
    mod_type: ModType,
    file_id: Option<String>,
) -> Result<(PathBuf, String)> {
    let file = get_latest_mod_version_curseforge(
        id.clone(),
        minecraft_version,
        mod_loader,
        mod_type,
        file_id,
    )
    .await?
    .ok_or_else(|| anyhow::anyhow!("noVersion"))?;
    let current_usage = settings.get_i64("curseforgeUsage")?.unwrap_or_default();
    settings.set_i64("curseforgeUsage", current_usage + 1)?;
    get_file(file.into(), id, event_sink).await
}

pub async fn identify_modpack_curseforge(
    mc_folder: &PathBuf,
    modpack: String,
) -> Result<Vec<IdentifiedMod>> {
    let modpack_folder = mc_folder.join("modpacks").join(&modpack);
    let existing_modpack: Vec<LocalModpack> = get_modpacks(mc_folder, false)?
        .into_iter()
        .filter(|existing| existing.name == modpack)
        .collect();
    if existing_modpack.is_empty() {
        return Err(anyhow::anyhow!("Modpack doesn't exist"));
    }
    let existing_modpack = existing_modpack.first().unwrap();
    let existing_files: Vec<String> = existing_modpack
        .mods
        .iter()
        .map(|mod_| {
            urlencoding::decode(&mod_.download_url)
                .unwrap_or_default()
                .to_string()
                .split('/')
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
        .map(|file| file.unwrap().file_name().to_string_lossy().to_string())
        .collect();

    let mut hashes = Vec::new();
    for file in unknown_files {
        let file = modpack_folder.join(file);
        let contents = get_jar_contents(file.to_string_lossy().as_ref());
        let hash = compute_hash(&contents);
        let mut hasher = sha1::Sha1::new();
        hasher.update(contents);
        let sha1 = hex::encode(hasher.finalize());
        hashes.push((
            hash,
            sha1,
            file.file_name().unwrap().to_string_lossy().to_string(),
        ));
    }

    let response = reqwest::Client::new()
        .post(format!("{}v1/fingerprints/{}", BASE_URL, MINECRAFT_ID))
        .header("User-Agent", get_user_agent())
        .header("X-API-Key", env!("ETERNAL_API_TOKEN"))
        .json(&serde_json::json!({
            "fingerprints": hashes.iter().map(|hash| hash.0).collect::<Vec<u32>>(),
        }))
        .send()
        .await?;
    let matches = response
        .json::<ExactMatchesResponse>()
        .await?
        .data
        .exact_matches;

    let mut mods = Vec::new();
    for match_ in matches {
        let file = match_.file;
        let hash = file.hashes.iter().find(|hash| hash.algo == 1).unwrap();
        let original_file = hashes
            .iter()
            .find(|(_, sha1, _)| sha1 == &hash.value)
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
