//! Local file cache utilities used by mod downloads.

use std::path::PathBuf;

use chrono::prelude::*;
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use sha1::{Digest, Sha1};
use tokio::sync::Mutex;

static CACHE_WRITE_LOCK: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));

/// Cache index entry describing a downloaded file in the shared cache.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheIndex {
    /// Last time the cached file was used.
    pub last_used_date: DateTime<Utc>,
    /// SHA-1 hash of the cached file contents.
    pub file_hash: String,
    /// Absolute path to the cached file on disk.
    pub file_name: String,
}

/// Initializes the cache directory and removes stale cache entries.
pub async fn init_cache() -> Result<(), anyhow::Error> {
    log::info!("Initializing mod cache");
    let cache_dir = dirs::cache_dir()
        .unwrap_or_default()
        .join("mrquantumoff.dev")
        .join("QuadrantNextCache");
    if !cache_dir.exists() {
        std::fs::create_dir_all(&cache_dir)?
    }
    let index_file = cache_dir.join("cacheIndex.json");

    if !index_file.exists() {
        std::fs::write(
            &index_file,
            serde_json::to_string_pretty(&Vec::<CacheIndex>::new())?,
        )?;
    }

    let mut config_raw = std::fs::read_to_string(&index_file)?;
    if serde_json::from_str::<Vec<CacheIndex>>(&config_raw).is_err() {
        std::fs::write(
            &index_file,
            serde_json::to_string_pretty(&Vec::<CacheIndex>::new())?,
        )?;
    }

    config_raw = std::fs::read_to_string(&index_file)?;
    let mut file_conts = serde_json::from_str::<Vec<CacheIndex>>(&config_raw)?;

    for index in file_conts.clone() {
        let is_old = Utc::now() - index.last_used_date;
        let file = PathBuf::from(&index.file_name);

        if is_old.num_days() >= 90 {
            log::info!("Removing stale cache entry: {}", index.file_name);
            if file.exists() {
                std::fs::remove_file(&file)?;
            }
            file_conts.retain(|cont| cont.file_hash != index.file_hash);
        }

        if !file.exists() {
            file_conts.retain(|cont| cont.file_hash != index.file_hash);
        }
    }

    std::fs::write(index_file, serde_json::to_string_pretty(&file_conts)?)?;
    Ok(())
}

/// Computes the SHA-1 hash of a file payload.
pub fn file_hash(file_bytes: &[u8]) -> String {
    let mut hasher = Sha1::new();
    hasher.update(file_bytes);
    let hash = hasher.finalize();
    hex::encode(hash)
}

/// Looks up a cached file by content hash.
pub async fn get_cache_index(file_hash: String) -> Result<Option<CacheIndex>, anyhow::Error> {
    let cache_dir = dirs::cache_dir()
        .unwrap_or_default()
        .join("mrquantumoff.dev")
        .join("QuadrantNextCache");
    init_cache().await?;
    let cache_config = cache_dir.join("cacheIndex.json");
    let config_raw = std::fs::read_to_string(cache_config)?;
    let file_conts: Vec<CacheIndex> = serde_json::from_str(&config_raw)?;
    let file_conts: Vec<CacheIndex> = file_conts
        .into_iter()
        .filter(|index| index.file_hash == file_hash)
        .collect();
    if file_conts.is_empty() {
        return Ok(None);
    }
    Ok(Some(file_conts[0].clone()))
}

/// Stores a file in the shared cache or refreshes an existing cache entry.
pub async fn add_cache_index(
    file_name: String,
    file_bytes: &[u8],
    file_hash: String,
) -> Result<PathBuf, anyhow::Error> {
    let _guard = CACHE_WRITE_LOCK.lock().await;
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

    let exists = file_conts
        .iter()
        .filter(|index| index.file_hash == file_hash)
        .collect::<Vec<&CacheIndex>>();
    let file_path: PathBuf;
    if !exists.is_empty() {
        log::info!("Cache entry for hash {file_hash} already exists, refreshing last-used date");
        file_path = PathBuf::from(exists[0].file_name.clone());
        let index = file_conts
            .iter()
            .position(|index| index.file_hash == file_hash)
            .unwrap();
        file_conts[index].last_used_date = Utc::now();
    } else {
        log::info!("Adding new cache entry: {file_name} (hash={file_hash})");
        let safe_name = PathBuf::from(file_name)
            .file_name()
            .ok_or_else(|| anyhow::anyhow!("Invalid cache file name"))?
            .to_string_lossy()
            .to_string();
        // Content-address the on-disk name so provider files with identical
        // names cannot overwrite one another in the shared cache.
        let new_file = cache_dir.join(format!(
            "{}-{safe_name}",
            &file_hash[..12.min(file_hash.len())]
        ));
        std::fs::write(&new_file, file_bytes)?;
        file_conts.push(CacheIndex {
            last_used_date: Utc::now(),
            file_hash,
            file_name: new_file.to_string_lossy().to_string(),
        });
        file_path = new_file;
    }

    std::fs::write(cache_config, serde_json::to_string_pretty(&file_conts)?)?;
    Ok(file_path)
}
