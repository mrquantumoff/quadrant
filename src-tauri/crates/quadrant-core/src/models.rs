use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Serialize, Deserialize, Debug, Clone, Eq, PartialEq)]
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
pub struct InstalledMod {
    pub id: String,
    pub source: ModSource,
    pub download_url: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, Eq, PartialEq)]
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
            "forge" => Self::Forge,
            "fabric" => Self::Fabric,
            "neoforge" => Self::NeoForge,
            "quilt" => Self::Quilt,
            "rift" => Self::Rift,
            _ => Self::Unknown,
        }
    }
}

impl ModLoader {
    pub fn to_curseforge_id(&self) -> i64 {
        match self {
            Self::Forge => 1,
            Self::Fabric => 4,
            Self::NeoForge => 6,
            Self::Rift => 999,
            Self::Quilt => 5,
            Self::Unknown => 0,
        }
    }
}

impl std::fmt::Display for ModLoader {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let label = match self {
            Self::Forge => "Forge",
            Self::Fabric => "Fabric",
            Self::NeoForge => "NeoForge",
            Self::Quilt => "Quilt",
            Self::Rift => "Rift",
            Self::Unknown => "Unknown",
        };
        f.write_str(label)
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
    pub unknown_mods: bool,
    pub is_applied: bool,
    pub last_synced: i64,
}

impl From<LocalModpack> for InstalledModpack {
    fn from(modpack: LocalModpack) -> Self {
        Self {
            name: modpack.name,
            version: modpack.version,
            mod_loader: modpack.mod_loader,
            mods: modpack.mods,
        }
    }
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct SyncInfo {
    pub last_synced: i64,
}

impl From<(InstalledModpack, bool, i64)> for LocalModpack {
    fn from(modpack: (InstalledModpack, bool, i64)) -> Self {
        Self {
            name: modpack.0.name,
            version: modpack.0.version,
            mod_loader: modpack.0.mod_loader,
            mods: modpack.0.mods,
            is_applied: modpack.1,
            last_synced: modpack.2,
            unknown_mods: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Article {
    pub title: String,
    pub link: String,
    pub summary: String,
    pub date: DateTime<Utc>,
    pub guid: String,
    pub new: bool,
}

pub fn modpack_path(mc_folder: &Path, modpack_name: &str) -> PathBuf {
    mc_folder.join("modpacks").join(modpack_name)
}
