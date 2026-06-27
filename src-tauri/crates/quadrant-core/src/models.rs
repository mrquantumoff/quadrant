//! Shared serialization-friendly data models used across core services.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Deserializer, Serialize, de::Error as DeError};
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

static QUADRANT_VERSION: OnceLock<String> = OnceLock::new();

pub fn set_quadrant_version(version: String) {
    let _ = QUADRANT_VERSION.set(version);
}

pub fn quadrant_version() -> String {
    QUADRANT_VERSION
        .get()
        .cloned()
        .unwrap_or_else(|| env!("CARGO_PKG_VERSION").to_string())
}

fn default_mod_config_version() -> String {
    "1".to_string()
}

/// Source provider for a mod or downloadable file.
#[derive(Serialize, Deserialize, Debug, Clone, Eq, PartialEq)]
pub enum ModSource {
    #[serde(rename = "ModSource.curseForge")]
    CurseForge,
    #[serde(rename = "ModSource.modRinth")]
    Modrinth,
    #[serde(rename = "ModSource.online")]
    Online,
}

/// Persisted representation of an installed mod entry.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InstalledMod {
    /// Human-readable mod name.
    #[serde(default)]
    pub name: String,
    /// Provider-specific mod identifier.
    pub id: String,
    /// Aggregate download count from the upstream provider.
    #[serde(default)]
    pub download_count: i64,
    /// Mod version label (e.g. "1.2.3").
    #[serde(default)]
    pub version: String,
    /// Broad content type ("Mod", "ResourcePack", "ShaderPack", "Unknown").
    #[serde(default)]
    pub mod_type: String,
    /// Source provider of the mod.
    pub source: ModSource,
    /// Provider slug used to build URLs.
    #[serde(default)]
    pub slug: String,
    /// Preview image URLs exposed by the provider.
    #[serde(default)]
    pub thumbnail_urls: Vec<String>,
    /// Human-readable description.
    #[serde(default)]
    pub description: String,
    /// License label, if known.
    #[serde(default)]
    pub license: String,
    /// Primary icon URL.
    #[serde(default)]
    pub mod_icon_url: String,
    /// URL of the installed file that was selected for this mod.
    pub download_url: String,
}

impl InstalledMod {
    /// Creates an `InstalledMod` with only the required fields populated;
    /// all optional fields default to empty/zero values.
    pub fn minimal(id: String, source: ModSource, download_url: String) -> Self {
        Self {
            id,
            source,
            download_url,
            name: String::new(),
            download_count: 0,
            version: String::new(),
            mod_type: String::new(),
            slug: String::new(),
            thumbnail_urls: Vec::new(),
            description: String::new(),
            license: String::new(),
            mod_icon_url: String::new(),
        }
    }
}

/// Supported mod loader families used throughout Quadrant.
#[derive(Serialize, Deserialize, Debug, Clone, Copy, Eq, PartialEq)]
pub enum ModLoader {
    #[serde(rename = "Forge")]
    Forge,
    #[serde(rename = "Fabric")]
    Fabric,
    #[serde(rename = "NeoForge")]
    NeoForge,
    #[serde(rename = "Babric")]
    Babric,
    #[serde(rename = "BTA (Babric)")]
    BtaBabric,
    #[serde(rename = "Java Agent")]
    JavaAgent,
    #[serde(rename = "Legacy Fabric")]
    LegacyFabric,
    #[serde(rename = "LiteLoader")]
    LiteLoader,
    #[serde(rename = "Risugami's ModLoader")]
    RisugamisModLoader,
    #[serde(rename = "NilLoader")]
    NilLoader,
    #[serde(rename = "Ornithe")]
    Ornithe,
    #[serde(rename = "Quilt")]
    Quilt,
    #[serde(rename = "Rift")]
    Rift,
    #[serde(rename = "Unknown")]
    Unknown,
}

impl From<String> for ModLoader {
    fn from(value: String) -> Self {
        match value.trim().to_lowercase().as_str() {
            "forge" => Self::Forge,
            "fabric" => Self::Fabric,
            "neoforge" => Self::NeoForge,
            "babric" => Self::Babric,
            "bta (babric)" | "bta-babric" | "bta babric" => Self::BtaBabric,
            "java agent" | "java-agent" => Self::JavaAgent,
            "legacy fabric" | "legacy-fabric" => Self::LegacyFabric,
            "liteloader" | "lite loader" | "lite-loader" => Self::LiteLoader,
            "risugami's modloader" | "risugamis modloader" | "risugami modloader" | "modloader" => {
                Self::RisugamisModLoader
            }
            "nilloader" | "nil loader" | "nil-loader" => Self::NilLoader,
            "ornithe" => Self::Ornithe,
            "quilt" => Self::Quilt,
            "rift" => Self::Rift,
            _ => Self::Unknown,
        }
    }
}

impl ModLoader {
    /// Returns the Modrinth loader/category slug used by provider queries.
    /// Display labels intentionally differ from API slugs for hyphenated loaders.
    pub fn modrinth_slug(&self) -> Option<&'static str> {
        match self {
            Self::Forge => Some("forge"),
            Self::Fabric => Some("fabric"),
            Self::NeoForge => Some("neoforge"),
            Self::Babric => Some("babric"),
            Self::BtaBabric => Some("bta-babric"),
            Self::JavaAgent => Some("java-agent"),
            Self::LegacyFabric => Some("legacy-fabric"),
            Self::LiteLoader => Some("liteloader"),
            Self::RisugamisModLoader => Some("modloader"),
            Self::NilLoader => Some("nilloader"),
            Self::Ornithe => Some("ornithe"),
            Self::Quilt => Some("quilt"),
            Self::Rift => Some("rift"),
            Self::Unknown => None,
        }
    }

    /// Returns the CurseForge mod loader identifier used by provider queries.
    pub fn curseforge_id(&self) -> Option<i64> {
        match self {
            Self::Forge => Some(1),
            Self::LiteLoader => Some(3),
            Self::Fabric => Some(4),
            Self::Quilt => Some(5),
            Self::NeoForge => Some(6),
            Self::Babric
            | Self::BtaBabric
            | Self::JavaAgent
            | Self::LegacyFabric
            | Self::RisugamisModLoader
            | Self::NilLoader
            | Self::Ornithe
            | Self::Rift
            | Self::Unknown => None,
        }
    }

    /// Returns the CurseForge mod loader identifier used by legacy call sites.
    pub fn to_curseforge_id(&self) -> i64 {
        self.curseforge_id().unwrap_or(0)
    }
}

impl std::fmt::Display for ModLoader {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let label = match self {
            Self::Forge => "Forge",
            Self::Fabric => "Fabric",
            Self::NeoForge => "NeoForge",
            Self::Babric => "Babric",
            Self::BtaBabric => "BTA (Babric)",
            Self::JavaAgent => "Java Agent",
            Self::LegacyFabric => "Legacy Fabric",
            Self::LiteLoader => "LiteLoader",
            Self::RisugamisModLoader => "Risugami's ModLoader",
            Self::NilLoader => "NilLoader",
            Self::Ornithe => "Ornithe",
            Self::Quilt => "Quilt",
            Self::Rift => "Rift",
            Self::Unknown => "Unknown",
        };
        f.write_str(label)
    }
}

/// On-disk modpack manifest representation.
#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct InstalledModpack {
    /// Schema version of the mod config file.
    #[serde(default = "default_mod_config_version")]
    pub mod_config_version: String,
    /// Quadrant version under which this file was last saved.
    #[serde(default)]
    pub quadrant_version: String,
    /// Human-readable modpack name.
    pub name: String,
    /// Minecraft version the modpack targets.
    pub version: String,
    /// Mod loader the modpack requires.
    pub mod_loader: ModLoader,
    /// Mods currently registered in the modpack manifest.
    pub mods: Vec<InstalledMod>,
}

/// Local modpack model enriched with frontend-oriented state.
#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct LocalModpack {
    /// Human-readable modpack name.
    pub name: String,
    /// Minecraft version the modpack targets.
    pub version: String,
    /// Mod loader the modpack requires.
    pub mod_loader: ModLoader,
    /// Mods currently registered in the modpack manifest.
    pub mods: Vec<InstalledMod>,
    /// Whether the modpack directory contains files not tracked by the manifest.
    pub unknown_mods: bool,
    /// Whether this modpack is currently applied as the active `mods` folder.
    pub is_applied: bool,
    /// Last successful sync time in milliseconds since the Unix epoch.
    #[serde(deserialize_with = "deserialize_integral_i64")]
    pub last_synced: i64,
    /// Stable synced modpack identifier when this modpack is linked to Quadrant Sync.
    pub modpack_id: Option<String>,
}

impl From<LocalModpack> for InstalledModpack {
    fn from(modpack: LocalModpack) -> Self {
        Self {
            mod_config_version: "2".to_string(),
            quadrant_version: quadrant_version(),
            name: modpack.name,
            version: modpack.version,
            mod_loader: modpack.mod_loader,
            mods: modpack.mods,
        }
    }
}

/// Sync metadata stored alongside a modpack.
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct SyncInfo {
    /// Last successful sync time in seconds since the Unix epoch.
    pub last_synced: i64,
    /// Stable synced modpack identifier when known.
    #[serde(default)]
    pub modpack_id: Option<String>,
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
            modpack_id: None,
            unknown_mods: false,
        }
    }
}

fn deserialize_integral_i64<'de, D>(deserializer: D) -> Result<i64, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Value::deserialize(deserializer)?;
    match value {
        Value::Number(number) => {
            if let Some(value) = number.as_i64() {
                return Ok(value);
            }
            if let Some(value) = number.as_u64() {
                return i64::try_from(value)
                    .map_err(|_| D::Error::custom("integer is out of range for i64"));
            }
            if let Some(value) = number.as_f64()
                && value.is_finite()
                && value.fract() == 0.0
                && value >= i64::MIN as f64
                && value <= i64::MAX as f64
            {
                return Ok(value as i64);
            }
            Err(D::Error::custom("expected an integer-valued number"))
        }
        other => Err(D::Error::custom(format!(
            "expected a number for integer deserialization, got {other}"
        ))),
    }
}

/// RSS article surfaced by the Quadrant news feed.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Article {
    /// Article title.
    pub title: String,
    /// Canonical article link.
    pub link: String,
    /// Article summary or description.
    pub summary: String,
    /// Publication timestamp.
    pub date: DateTime<Utc>,
    /// Stable feed item GUID.
    pub guid: String,
    /// Whether the article should be treated as recent by the app.
    pub new: bool,
}

/// Returns the canonical filesystem path for a named modpack.
pub fn modpack_path(mc_folder: &Path, modpack_name: &str) -> PathBuf {
    mc_folder.join("modpacks").join(modpack_name)
}
