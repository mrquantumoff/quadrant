use serde::{Deserialize, Serialize};

use crate::{
    Result,
    account::QNT_BASE_URL,
    models::InstalledModpack,
    ports::{SecretStore, SettingsStore},
};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuadrantShareSubmissionResponse {
    pub code: i32,
    pub uses_left: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuadrantShareSubmission {
    pub hardware_id: String,
    pub mod_config: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuadrantShareResponse {
    pub code: i32,
    pub mod_config: String,
}

pub async fn share_modpack_raw(
    settings_store: &impl SettingsStore,
    secret_store: &impl SecretStore,
    user_agent: &str,
    mod_config: InstalledModpack,
    api_key: &str,
) -> Result<QuadrantShareSubmissionResponse> {
    let data_collection_enabled = settings_store.get_bool("collectUserData")?.unwrap_or(false);
    if !data_collection_enabled {
        return Err(anyhow::anyhow!("enableDataSharing"));
    }

    let token = secret_store.get_secret("accountToken")?;
    let mut url = format!("{}/quadrant/share/submit", QNT_BASE_URL);
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

pub async fn get_quadrant_share_modpack(
    user_agent: &str,
    api_key: &str,
    code: String,
) -> Result<InstalledModpack> {
    let response = reqwest::Client::new()
        .get(format!("{}/quadrant/share/get", QNT_BASE_URL))
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
