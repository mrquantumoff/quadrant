use std::path::PathBuf;

use chrono::prelude::*;
use serde::{Deserialize, Serialize};
use sha1::{Digest, Sha1};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheIndex {
    pub last_used_date: DateTime<Utc>,
    pub file_hash: String,
    pub file_name: String,
}

pub async fn init_cache() -> Result<(), anyhow::Error> {
    let cache_dir = dirs::cache_dir()
        .unwrap_or_default()
        .join("mrquantumoff.dev")
        .join("QuadrantNextCache");
    if !cache_dir.exists() {
        std::fs::create_dir_all(&cache_dir)?
    }
    let config_file = cache_dir.join("cacheIndex.json");

    let mut config_raw = std::fs::read_to_string(&config_file)?;

    let file_conts = serde_json::from_str::<Vec<CacheIndex>>(&config_raw);

    if file_conts.is_err() {
        let empty_index: Vec<CacheIndex> = Vec::new();
        std::fs::write(
            &config_file,
            serde_json::to_string_pretty(&empty_index)?.as_bytes(),
        )?;
    }

    config_raw = std::fs::read_to_string(&config_file)?;

    let mut file_conts = serde_json::from_str::<Vec<CacheIndex>>(&config_raw)?;

    for index in file_conts.clone() {
        // Check if the file is older than 90 days
        log::info!("Checking if file hash is old: {}", &index.file_hash);
        let is_old = Utc::now() - index.last_used_date;

        if is_old.num_days() >= 90 {
            let file_path = PathBuf::from(&index.file_name);
            std::fs::remove_file(file_path)?;
            log::info!("Removing file from cache: {}", index.file_name);
            file_conts.retain(|cont| cont.file_hash != index.file_hash);
        }
    }
    // Save the new file conts
    std::fs::write(
        config_file,
        serde_json::to_string_pretty(&file_conts)?.as_bytes(),
    )?;

    Ok(())
}

pub fn file_hash(file_bytes: &[u8]) -> String {
    let mut hasher = Sha1::new();
    hasher.update(file_bytes);
    let hash = hasher.finalize();
    hex::encode(hash)
}

pub async fn get_cache_index(file_hash: String) -> Result<Option<CacheIndex>, anyhow::Error> {
    let cache_dir = dirs::cache_dir()
        .unwrap_or_default()
        .join("mrquantumoff.dev")
        .join("QuadrantNextCache");
    init_cache().await?;
    log::info!("Getting cache index for file hash: {}", &file_hash);
    let cache_config = cache_dir.join("cacheIndex.json");
    let config_raw = std::fs::read_to_string(cache_config)?;
    let file_conts: Vec<CacheIndex> = serde_json::from_str(&config_raw)?;
    let file_conts: Vec<CacheIndex> = file_conts
        .into_iter()
        .filter(|index| index.file_hash == file_hash)
        .collect();
    if file_conts.is_empty() {
        log::info!("Cache for file hash {} wasn't found", &file_hash);

        return Ok(None);
    }
    log::info!("Found cache for file hash: {}", &file_hash);
    Ok(Some(file_conts[0].clone()))
}

pub async fn add_cache_index(
    file_name: String,
    file_bytes: &[u8],
    file_hash: String,
) -> Result<PathBuf, anyhow::Error> {
    let cache_dir = dirs::cache_dir()
        .unwrap_or_default()
        .join("mrquantumoff.dev")
        .join("QuadrantNextCache");
    if !cache_dir.exists() {
        init_cache().await?;
    }
    let cache_config = cache_dir.join("cacheIndex.json");

    let config_raw = std::fs::read_to_string(&cache_config)?;

    let mut file_conts: Vec<CacheIndex> = serde_json::from_str(&config_raw)?;

    // Check if the file already exists
    let exists = file_conts
        .iter()
        .filter(|index| index.file_hash == file_hash)
        .collect::<Vec<&CacheIndex>>();
    let file_path: PathBuf;
    if !exists.is_empty() {
        file_path = PathBuf::from(exists[0].file_name.clone());
        // Update the file conts with the new last used date of the existing file
        // Index of the existing file
        let index = file_conts
            .iter()
            .position(|index| index.file_hash == file_hash)
            .unwrap();
        file_conts[index].last_used_date = Utc::now();
    } else {
        let new_file = cache_dir.join(file_name);
        std::fs::write(&new_file, file_bytes)?;
        file_conts.push(CacheIndex {
            last_used_date: Utc::now(),
            file_hash,
            file_name: new_file.to_str().unwrap().to_string(),
        });
        file_path = new_file;
    }

    std::fs::write(
        cache_config,
        serde_json::to_string_pretty(&file_conts)?.as_bytes(),
    )?;
    Ok(file_path)
}
