use crate::mc_mod::get_user_agent;
use crate::mc_mod::Mod;
use crate::mc_mod::ModType;
use crate::modpacks::general::ModLoader;
use chrono::prelude::*;
use serde::Deserialize;
use serde::Serialize;
use std::path::PathBuf;
use tauri::AppHandle;
use tauri_plugin_http::reqwest;
use tauri_plugin_store::StoreExt;

use http_cache_reqwest::{Cache, CacheMode, HttpCache, HttpCacheOptions, MokaManager};
use reqwest_middleware::ClientBuilder;

use super::get_file;
use super::get_mod_url;
use super::GetModArgs;
use super::ModSource;
use super::SearchModsArgs;

#[tauri::command]
pub async fn search_mods_modrinth(
    app: AppHandle,
    args: SearchModsArgs,
) -> Result<Vec<Mod>, tauri::Error> {
    let mut mod_type = args.mod_type.to_string().to_lowercase();
    if mod_type == "shaderpack" {
        mod_type = "shader".to_string();
    }

    let mod_type = ModType::from(mod_type);

    let mut facets = format!("[\"project_type:{}\"]", &mod_type.to_string());

    let store = app.store("config.json").map_err(anyhow::Error::from)?;

    if args.filter_on {
        let last_used_version: String = store
            .get("lastUsedVersion")
            .unwrap_or_else(|| serde_json::Value::String("".to_string()))
            .to_string()
            .replace("\"", "");
        facets = format!("{},[\"versions:{}\"]", facets, last_used_version);
        let last_used_api: String = store
            .get("lastUsedAPI")
            .unwrap_or_else(|| serde_json::Value::String("".to_string()))
            .to_string()
            .to_lowercase()
            .replace("\"", "");
        if mod_type == ModType::Mod {
            facets = format!("{},[\"categories:{}\"]", facets, last_used_api);
        }
    }

    let raw_uri = format!(
        "https://api.modrinth.com/v2/search?query={}&limit=100&facets=[{}]",
        args.query, facets
    );

    // log::info!("Raw URI: {}", raw_uri);

    let client = ClientBuilder::new(reqwest::Client::new())
        .with(Cache(HttpCache {
            mode: CacheMode::Default,
            options: HttpCacheOptions::default(),
            manager: MokaManager::default(),
        }))
        .build();
    let request = client
        .get(&raw_uri)
        .header("User-Agent", get_user_agent())
        .build()
        .unwrap();
    let res = client.execute(request).await.map_err(anyhow::Error::from)?;
    let response_json: serde_json::Value = res.json().await.map_err(anyhow::Error::from)?;

    let mut mods: Vec<Mod> = Vec::new();
    if let Some(hits) = response_json["hits"].as_array() {
        for mod_data in hits {
            let name = mod_data["title"].as_str().unwrap_or_default().to_string();
            let description = mod_data["description"]
                .as_str()
                .unwrap_or_default()
                .to_string();
            let download_count = mod_data["downloads"].as_i64().unwrap_or_default();
            let id = mod_data["project_id"]
                .as_str()
                .unwrap_or_default()
                .to_string();
            let slug = mod_data["slug"].as_str().unwrap_or_default().to_string();
            let mut icon =
                "https://raw.githubusercontent.com/mrquantumoff/quadrant/next/public/logonobg.png"
                    .to_string();

            let mut screenshots = Vec::new();
            if let Some(gallery) = mod_data["gallery"].as_array() {
                for screenshot in gallery {
                    if let Some(url) = screenshot.as_str() {
                        screenshots.push(url.to_string());
                    }
                }
            }

            if let Some(mod_icon_url) = mod_data["icon_url"].as_str() {
                if !mod_icon_url.trim().is_empty() {
                    icon = mod_icon_url.to_string();
                }
            }
            let license = mod_data["license"].as_str().unwrap_or_default().to_string();

            mods.push(Mod {
                name,
                id,
                download_count,
                version: String::new(),
                mod_type,
                source: ModSource::Modrinth,
                slug: slug.clone(),
                thumbnail_urls: screenshots,
                url: get_mod_url(slug, mod_type, ModSource::Modrinth),
                description,
                license,
                mod_icon_url: icon,
                downloadable: true,
                show_previous_version: false,
                new_version: None,
                deleteable: false,
                autoinstallable: args.filter_on,
            });
        }
    }

    Ok(mods)
}
#[tauri::command]
pub async fn get_mod_modrinth(args: GetModArgs) -> Result<Mod, tauri::Error> {
    let client = reqwest::Client::new();
    let request = client
        .get(format!("https://api.modrinth.com/v2/project/{}", args.id))
        .header("User-Agent", get_user_agent())
        .build()
        .unwrap();
    let res = client.execute(request).await.map_err(anyhow::Error::from)?;
    let res_json: serde_json::Value = res.json().await.map_err(anyhow::Error::from)?;

    let mut screenshots = Vec::new();
    if let Some(gallery) = res_json["gallery"].as_array() {
        for screenshot in gallery {
            if let Some(url) = screenshot["url"].as_str() {
                screenshots.push(url.to_string());
            }
        }
    }

    let mod_class_string = res_json["project_type"].as_str().unwrap_or_default();
    let mod_type = match mod_class_string {
        "mod" => ModType::Mod,
        "resourcepack" => ModType::ResourcePack,
        "shader" => ModType::ShaderPack,
        _ => return Err(anyhow::Error::msg("Unsupported Mod Type").into()),
    };

    let final_mod = Mod {
        name: res_json["title"].as_str().unwrap_or_default().to_string(),
        id: args.id.clone(),
        download_count: res_json["downloads"].as_i64().unwrap_or_default(),
        version: res_json["versions"]
            .as_array()
            .and_then(|v| v.first())
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string(),
        mod_type,
        source: ModSource::Modrinth,
        slug: res_json["slug"].as_str().unwrap_or_default().to_string(),
        thumbnail_urls: screenshots,
        url: get_mod_url(
            res_json["slug"].as_str().unwrap_or_default().to_string(),
            mod_type,
            ModSource::Modrinth,
        ),
        description: res_json["description"]
            .as_str()
            .unwrap_or_default()
            .to_string(),
        license: res_json["license"].as_str().unwrap_or_default().to_string(),
        mod_icon_url: res_json["icon_url"]
            .as_str()
            .unwrap_or_default()
            .to_string(),
        downloadable: args.downloadable,
        show_previous_version: args.show_previous_version,
        new_version: None,
        deleteable: args.deletable,
        autoinstallable: false,
    };

    Ok(final_mod)
}

#[tauri::command]
pub async fn get_mod_owners_modrinth(id: String) -> Result<Vec<String>, tauri::Error> {
    let client = reqwest::Client::new();
    let request = client
        .get(format!(
            "https://api.modrinth.com/v2/project/{}/members",
            id
        ))
        .header("User-Agent", get_user_agent())
        .build()
        .unwrap();
    let res = client.execute(request).await.map_err(anyhow::Error::from)?;
    let res_json: serde_json::Value = res.json().await.map_err(anyhow::Error::from)?;
    let mut owners = Vec::new();
    if let Some(members) = res_json.as_array() {
        for member in members {
            if let Some(username) = member["user"]["username"].as_str() {
                owners.push(username.to_string());
            }
        }
    }

    Ok(owners)
}

#[tauri::command]
pub async fn get_mod_deps_modrinth(id: String) -> Result<Vec<Mod>, tauri::Error> {
    let client = reqwest::Client::new();
    let request = client
        .get(format!(
            "https://api.modrinth.com/v2/project/{}/dependencies",
            id
        ))
        .header("User-Agent", get_user_agent())
        .build()
        .unwrap();
    let res = client.execute(request).await.map_err(anyhow::Error::from)?;
    let res_json: serde_json::Value = res.json().await.map_err(anyhow::Error::from)?;
    let mut dependencies: Vec<String> = Vec::new();
    if let Some(deps) = res_json["projects"].as_array() {
        for dependency in deps {
            if let Some(id) = dependency["id"].as_str() {
                dependencies.push(id.to_string());
            }
        }
    }

    let mut mods: Vec<Mod> = Vec::new();
    for dependency in dependencies {
        mods.push(
            get_mod_modrinth(GetModArgs {
                deletable: false,
                id: dependency,
                downloadable: true,
                // These values aren't used unless show_previous_version is true
                show_previous_version: false,
                version_target: "".to_string(),
                modpack: "".to_string(),
                mod_loader: ModLoader::Unknown,
            })
            .await?,
        );
    }

    Ok(mods)
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ModrinthVersion {
    pub date_published: DateTime<Utc>,
    pub files: Vec<ModrinthFile>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ModrinthHash {
    pub sha512: String,
    pub sha1: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ModrinthFile {
    pub hashes: ModrinthHash,
    pub url: String,
    pub filename: String,
    pub primary: bool,
    pub size: u64,
}

pub async fn get_latest_mod_version_modrinth(
    id: String,
    minecraft_version: String,
    mod_loader: ModLoader,
    mod_type: ModType,
) -> Result<Option<ModrinthFile>, anyhow::Error> {
    let client = reqwest::Client::new();
    let mut query = vec![("game_versions", format!("[\"{}\"]", minecraft_version))];
    if mod_type == ModType::Mod {
        query.push((
            "loaders",
            format!("[\"{}\"]", mod_loader.to_string().to_lowercase()),
        ));
    }

    let final_url = format!("https://api.modrinth.com/v2/project/{}/version", id);

    log::info!("Final URL: {}", final_url);

    let request = client
        .get(final_url)
        .query(query.as_slice())
        .header("User-Agent", get_user_agent())
        .build()?;
    let res = client.execute(request).await?;

    let body = res.text().await?;

    let mut res_json: Vec<ModrinthVersion> = serde_json::from_str(&body)?;
    res_json.sort_by(|a, b| b.date_published.cmp(&a.date_published).reverse());
    if res_json.is_empty() {
        return Err(anyhow::Error::msg("noVersion"));
    }
    let last_file = res_json[0].files.iter().find(|file| file.primary);
    log::info!("Got the update (if exists)");

    let last_file = last_file.cloned();
    Ok(last_file)
}

pub async fn download_mod_modrinth(
    id: String,
    minecraft_version: String,
    mod_loader: ModLoader,
    mod_type: ModType,
    app: AppHandle,
) -> Result<(PathBuf, String), anyhow::Error> {
    let file = get_latest_mod_version_modrinth(id.clone(), minecraft_version, mod_loader, mod_type)
        .await?;
    if file.is_none() {
        return Err(anyhow::Error::msg("noVersion"));
    }
    let file = file.unwrap();
    let store = app.store("config.json").unwrap();
    store.set(
        "modrinthUsage",
        store
            .get("modrinthUsage")
            .unwrap()
            .as_i64()
            .unwrap_or_else(|| 0)
            + 1,
    );
    get_file(file.into(), id, app).await
}
