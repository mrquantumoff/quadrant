//! Quadrant Share submission and retrieval APIs.

use serde::{Deserialize, Serialize};

use crate::{
    Result,
    account::backend_base_url,
    models::InstalledModpack,
    ports::{SecretStore, SettingsStore},
};

/// Response returned after sharing a modpack.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuadrantShareSubmissionResponse {
    /// Share code returned by the backend.
    pub code: i32,
    /// Remaining number of allowed uses for the share submission.
    pub uses_left: i64,
}

/// Payload submitted when sharing a modpack.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuadrantShareSubmission {
    /// Stable installation identifier of the submitting host.
    pub hardware_id: String,
    /// Serialized modpack manifest.
    pub mod_config: String,
}

/// Response returned when resolving a share code.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuadrantShareResponse {
    /// Share code returned by the backend.
    pub code: i32,
    /// Serialized modpack manifest.
    pub mod_config: String,
}

/// Submits a modpack to Quadrant Share using the current settings and account state.
pub async fn share_modpack_raw(
    settings_store: &impl SettingsStore,
    secret_store: &impl SecretStore,
    user_agent: &str,
    mod_config: InstalledModpack,
    api_key: &str,
) -> Result<QuadrantShareSubmissionResponse> {
    log::info!("Sharing modpack: {}", mod_config.name);
    let data_collection_enabled = settings_store.get_bool("collectUserData")?.unwrap_or(false);
    if !data_collection_enabled {
        log::info!("Modpack share aborted: data collection is disabled");
        return Err(anyhow::anyhow!("enableDataSharing"));
    }

    let token = secret_store.get_secret("accountToken")?;
    let mut url = format!("{}/quadrant/share/submit", backend_base_url());
    if token.is_some() {
        url = format!("{}/id", url);
    }

    let mut request = reqwest::Client::new()
        .post(&url)
        .header("User-Agent", user_agent)
        .body(serde_json::to_string_pretty(&QuadrantShareSubmission {
            hardware_id: settings_store.get_string("hardwareId")?.unwrap_or_default(),
            mod_config: serde_json::to_string_pretty(&mod_config)?,
        })?);

    if let Some(token) = token {
        request = request.bearer_auth(token);
    } else {
        request = request.header("Authorization", api_key);
    }

    Ok(request
        .send()
        .await?
        .json::<QuadrantShareSubmissionResponse>()
        .await?)
}

/// Resolves a share code into an installed modpack manifest.
pub async fn get_quadrant_share_modpack(
    user_agent: &str,
    api_key: &str,
    code: String,
) -> Result<InstalledModpack> {
    log::info!("Fetching shared modpack with code: {code}");
    let response = reqwest::Client::new()
        .get(format!("{}/quadrant/share/get", backend_base_url()))
        .query(&[("code", code)])
        .header("User-Agent", user_agent)
        .header("Authorization", api_key)
        .send()
        .await?
        .text()
        .await?;
    let response: QuadrantShareResponse = serde_json::from_str(&response)?;
    Ok(serde_json::from_str(&response.mod_config)?)
}
