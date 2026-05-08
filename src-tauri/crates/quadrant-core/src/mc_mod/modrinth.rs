use std::path::PathBuf;

use chrono::prelude::*;
use serde::{Deserialize, Serialize};
use sha1::{Digest, Sha1};

use crate::{
    Result,
    models::{LocalModpack, ModLoader, ModSource},
    modpacks::get_modpacks,
    ports::{EventSink, SettingsStore},
};

use super::http::provider_cached_client;
use super::{
    GetModArgs, IdentifiedMod, InstalledMod, Mod, ModType, SearchModsArgs, UniversalModFile,
    get_file, get_mod_url,
};

pub(crate) fn modrinth_api_base() -> String {
    #[cfg(test)]
    if let Ok(base_url) = std::env::var("QUADRANT_TEST_MODRINTH_API_BASE") {
        return base_url;
    }

    "https://api.modrinth.com".to_string()
}

pub async fn search_mods_modrinth(
    settings: &impl SettingsStore,
    args: SearchModsArgs,
) -> Result<Vec<Mod>> {
    let mut mod_type = args.mod_type.to_lowercase();
    if mod_type == "shaderpack" {
        mod_type = "shader".to_string();
    }

    let mod_type = ModType::from(mod_type);
    let mut facets = format!("[\"project_type:{}\"]", mod_type);

    if args.filter_on {
        let last_used_version = settings.get_string("lastUsedVersion")?.unwrap_or_default();
        facets = format!("{},[\"versions:{}\"]", facets, last_used_version);
        let last_used_api = settings
            .get_string("lastUsedAPI")?
            .unwrap_or_default()
            .to_lowercase();
        if mod_type == ModType::Mod {
            facets = format!("{},[\"categories:{}\"]", facets, last_used_api);
        }
    }

    let raw_uri = format!(
        "{}/v2/search?query={}&limit=100&facets=[{}]",
        modrinth_api_base(),
        args.query,
        facets
    );

    let response_json: serde_json::Value = provider_cached_client()
        .get(&raw_uri)
        .send()
        .await?
        .json()
        .await?;

    let mut mods = Vec::new();
    if let Some(hits) = response_json["hits"].as_array() {
        for mod_data in hits {
            let mut screenshots = Vec::new();
            if let Some(gallery) = mod_data["gallery"].as_array() {
                for screenshot in gallery {
                    if let Some(url) = screenshot.as_str() {
                        screenshots.push(url.to_string());
                    }
                }
            }

            let icon = mod_data["icon_url"]
                .as_str()
                .filter(|value| !value.trim().is_empty())
                .unwrap_or(
                    "https://git.mrquantumoff.dev/quadrant/quadrant/raw/branch/next/public/logoNoBg.png",
                )
                .to_string();
            let slug = mod_data["slug"].as_str().unwrap_or_default().to_string();

            mods.push(Mod {
                name: mod_data["title"].as_str().unwrap_or_default().to_string(),
                id: mod_data["project_id"]
                    .as_str()
                    .unwrap_or_default()
                    .to_string(),
                download_count: mod_data["downloads"].as_i64().unwrap_or_default(),
                version: String::new(),
                mod_type,
                source: ModSource::Modrinth,
                slug: slug.clone(),
                thumbnail_urls: screenshots,
                url: get_mod_url(slug, mod_type, ModSource::Modrinth),
                description: mod_data["description"]
                    .as_str()
                    .unwrap_or_default()
                    .to_string(),
                license: mod_data["license"].as_str().unwrap_or_default().to_string(),
                mod_icon_url: icon,
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

pub async fn get_mod_modrinth(args: GetModArgs) -> Result<Mod> {
    let res_json: serde_json::Value = provider_cached_client()
        .get(format!("{}/v2/project/{}", modrinth_api_base(), args.id))
        .send()
        .await?
        .json()
        .await?;

    let mut screenshots = Vec::new();
    if let Some(gallery) = res_json["gallery"].as_array() {
        for screenshot in gallery {
            if let Some(url) = screenshot["url"].as_str() {
                screenshots.push(url.to_string());
            }
        }
    }

    let mod_type = match res_json["project_type"].as_str().unwrap_or_default() {
        "mod" => ModType::Mod,
        "resourcepack" => ModType::ResourcePack,
        "shader" => ModType::ShaderPack,
        _ => return Err(anyhow::anyhow!("Unsupported Mod Type")),
    };

    Ok(Mod {
        name: res_json["title"].as_str().unwrap_or_default().to_string(),
        id: args.id.clone(),
        download_count: res_json["downloads"].as_i64().unwrap_or_default(),
        version: res_json["versions"]
            .as_array()
            .and_then(|versions| versions.first())
            .and_then(|version| version.as_str())
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
        selectable: args.selectable,
        select_url: args.select_url,
        modpack: Some(args.modpack),
    })
}

pub async fn get_mod_owners_modrinth(id: String) -> Result<Vec<String>> {
    let res_json: serde_json::Value = provider_cached_client()
        .get(format!("{}/v2/project/{}/members", modrinth_api_base(), id))
        .send()
        .await?
        .json()
        .await?;
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

pub async fn get_mod_deps_modrinth(id: String) -> Result<Vec<Mod>> {
    let res_json: serde_json::Value = provider_cached_client()
        .get(format!(
            "{}/v2/project/{}/dependencies",
            modrinth_api_base(),
            id
        ))
        .send()
        .await?
        .json()
        .await?;
    let mut dependencies = Vec::new();
    if let Some(deps) = res_json["projects"].as_array() {
        for dependency in deps {
            if let Some(id) = dependency["id"].as_str() {
                dependencies.push(id.to_string());
            }
        }
    }

    let mut mods = Vec::new();
    for dependency in dependencies {
        mods.push(
            get_mod_modrinth(GetModArgs {
                deletable: false,
                id: dependency,
                downloadable: true,
                show_previous_version: false,
                version_target: String::new(),
                modpack: String::new(),
                mod_loader: ModLoader::Unknown,
                selectable: false,
                select_url: None,
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

impl From<ModrinthFile> for UniversalModFile {
    fn from(value: ModrinthFile) -> Self {
        Self {
            id: None,
            file_name: value.filename,
            download_url: value.url,
            sha1: value.hashes.sha1,
            size: value.size,
        }
    }
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ModrinthVersionIdentifier {
    pub files: Vec<ModrinthFile>,
    pub project_id: String,
}

pub async fn get_latest_mod_version_modrinth(
    id: String,
    minecraft_version: String,
    mod_loader: ModLoader,
    mod_type: ModType,
) -> Result<Option<ModrinthFile>> {
    let mut query = vec![("game_versions", format!("[\"{}\"]", minecraft_version))];
    if mod_type == ModType::Mod {
        query.push((
            "loaders",
            format!("[\"{}\"]", mod_loader.to_string().to_lowercase()),
        ));
    }
    let url = reqwest::Url::parse_with_params(
        format!("{}/v2/project/{}/version", modrinth_api_base(), id).as_str(),
        query.iter().map(|(key, value)| (*key, value.as_str())),
    )?;

    let response = provider_cached_client().get(url).send().await?;

    let mut res_json: Vec<ModrinthVersion> = serde_json::from_str(&response.text().await?)?;
    res_json.sort_by(|a, b| b.date_published.cmp(&a.date_published));
    if res_json.is_empty() {
        return Err(anyhow::anyhow!("noVersion"));
    }
    Ok(res_json[0].files.iter().find(|file| file.primary).cloned())
}

pub async fn download_mod_modrinth(
    settings: &impl SettingsStore,
    event_sink: &impl EventSink,
    id: String,
    minecraft_version: String,
    mod_loader: ModLoader,
    mod_type: ModType,
) -> Result<(PathBuf, String)> {
    log::info!("Downloading Modrinth mod {id} for {minecraft_version} ({mod_loader:?})");
    let file = get_latest_mod_version_modrinth(id.clone(), minecraft_version, mod_loader, mod_type)
        .await?
        .ok_or_else(|| anyhow::anyhow!("noVersion"))?;
    let current_usage = settings.get_i64("modrinthUsage")?.unwrap_or_default();
    settings.set_i64("modrinthUsage", current_usage + 1)?;
    get_file(file.into(), id, event_sink).await
}

pub async fn identify_modpack_modrinth(
    mc_folder: &PathBuf,
    modpack: String,
) -> Result<Vec<IdentifiedMod>> {
    log::info!("Identifying Modrinth mods in modpack \"{modpack}\"");
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

    let mut mods = Vec::new();
    for file in unknown_files {
        let original_file_name = file.clone();
        let file = modpack_folder.join(file);
        let mut hasher = Sha1::new();
        hasher.update(std::fs::read(file)?);
        let hash = hex::encode(hasher.finalize());
        let res = provider_cached_client()
            .get(format!("{}/v2/version_file/{}", modrinth_api_base(), hash))
            .send()
            .await?;
        let identifier = match res.json::<ModrinthVersionIdentifier>().await {
            Ok(identifier) => identifier,
            Err(_) => continue,
        };
        let file = match identifier
            .files
            .iter()
            .find(|file| file.hashes.sha1 == hash)
        {
            Some(file) => file,
            None => continue,
        };
        mods.push(IdentifiedMod {
            installed_mod: InstalledMod {
                download_url: file.url.clone(),
                id: identifier.project_id,
                source: ModSource::Modrinth,
            },
            file_name: original_file_name,
        });
    }

    Ok(mods)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        mc_mod::http::{PROVIDER_HTTP_TEST_MUTEX, clear_provider_http_cache},
        models::{InstalledModpack, ModLoader},
    };
    use httpmock::prelude::*;
    use serde_json::json;
    use tempfile::tempdir;

    fn modrinth_get_mod_args(id: &str) -> GetModArgs {
        GetModArgs {
            id: id.to_string(),
            downloadable: true,
            show_previous_version: false,
            deletable: false,
            version_target: String::new(),
            mod_loader: ModLoader::Fabric,
            modpack: String::new(),
            selectable: false,
            select_url: None,
        }
    }

    fn setup_modpack(mc_folder: &std::path::Path, name: &str) {
        let modpack_dir = mc_folder.join("modpacks").join(name);
        std::fs::create_dir_all(&modpack_dir).unwrap();
        std::fs::write(
            modpack_dir.join("modConfig.json"),
            serde_json::to_vec(&InstalledModpack {
                name: name.to_string(),
                version: "1.20.1".to_string(),
                mod_loader: ModLoader::Fabric,
                mods: Vec::new(),
            })
            .unwrap(),
        )
        .unwrap();
    }

    #[tokio::test]
    async fn get_mod_modrinth_uses_shared_http_cache() {
        let _guard = PROVIDER_HTTP_TEST_MUTEX.lock().await;
        clear_provider_http_cache().await;

        let server = MockServer::start();
        unsafe {
            std::env::set_var("QUADRANT_TEST_MODRINTH_API_BASE", server.base_url());
        }

        let project = server.mock(|when, then| {
            when.method(GET).path("/v2/project/demo-mod");
            then.status(200)
                .header("cache-control", "public, max-age=300")
                .json_body(json!({
                    "title": "Demo Mod",
                    "downloads": 42,
                    "versions": ["1.0.0"],
                    "project_type": "mod",
                    "slug": "demo-mod",
                    "description": "cached",
                    "license": "MIT",
                    "icon_url": "https://example.invalid/icon.png",
                    "gallery": [{ "url": "https://example.invalid/screenshot.png" }]
                }));
        });

        let args = modrinth_get_mod_args("demo-mod");
        get_mod_modrinth(args.clone()).await.unwrap();
        get_mod_modrinth(args).await.unwrap();

        project.assert_calls(1);

        unsafe {
            std::env::remove_var("QUADRANT_TEST_MODRINTH_API_BASE");
        }
        clear_provider_http_cache().await;
    }

    #[tokio::test]
    async fn identify_modpack_modrinth_uses_shared_http_cache() {
        let _guard = PROVIDER_HTTP_TEST_MUTEX.lock().await;
        clear_provider_http_cache().await;

        let server = MockServer::start();
        unsafe {
            std::env::set_var("QUADRANT_TEST_MODRINTH_API_BASE", server.base_url());
        }

        let temp_dir = tempdir().unwrap();
        let mc_folder = temp_dir.path().join(".minecraft");
        let modpack_dir = mc_folder.join("modpacks").join("alpha");
        setup_modpack(&mc_folder, "alpha");

        let file_bytes = b"modrinth-jar";
        let mut hasher = Sha1::new();
        hasher.update(file_bytes);
        let hash = hex::encode(hasher.finalize());
        std::fs::write(modpack_dir.join("unknown.jar"), file_bytes).unwrap();

        let version_lookup = server.mock(|when, then| {
            when.method(GET)
                .path(format!("/v2/version_file/{hash}").as_str());
            then.status(200)
                .header("cache-control", "public, max-age=300")
                .json_body(json!({
                    "files": [{
                        "hashes": {
                            "sha512": "unused",
                            "sha1": hash
                        },
                        "url": "https://example.invalid/mod.jar",
                        "filename": "unknown.jar",
                        "primary": true,
                        "size": 12
                    }],
                    "project_id": "demo-project"
                }));
        });

        let first = identify_modpack_modrinth(&mc_folder, "alpha".to_string())
            .await
            .unwrap();
        let second = identify_modpack_modrinth(&mc_folder, "alpha".to_string())
            .await
            .unwrap();

        assert_eq!(first.len(), 1);
        assert_eq!(second.len(), 1);
        version_lookup.assert_calls(1);

        unsafe {
            std::env::remove_var("QUADRANT_TEST_MODRINTH_API_BASE");
        }
        clear_provider_http_cache().await;
    }
}
