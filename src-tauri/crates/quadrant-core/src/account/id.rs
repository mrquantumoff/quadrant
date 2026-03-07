//! Account identity, login, refresh, and notification APIs.

use std::collections::HashMap;

use reqwest::StatusCode;
use serde::{Deserialize, Serialize};

use crate::{
    Result,
    account::{QNT_BASE_URL, get_account_token, get_refresh_token, set_secret},
    ports::SecretStore,
};

use super::quadrant_sync::SyncedModpack;

/// Account profile returned by the Quadrant backend.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccountInfo {
    /// Stable account identifier.
    pub id: String,
    /// Display name.
    pub name: String,
    /// Email address associated with the account.
    pub email: String,
    /// Maximum synced modpack quota for the account.
    pub quadrant_sync_limit: i32,
    /// Maximum share quota for the account.
    pub quadrant_share_limit: i32,
    /// Login or username.
    pub login: String,
    /// Current notification list.
    pub notifications: Vec<Notification>,
}

/// Account notification returned by the Quadrant backend.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Notification {
    /// Stable notification identifier.
    pub notification_id: String,
    /// Owning user identifier.
    pub user_id: String,
    /// Human-readable notification message.
    pub message: String,
    /// Creation timestamp in seconds since the Unix epoch.
    pub created_at: i64,
    /// Whether the notification has been marked as read.
    pub read: bool,
}

/// OAuth token response returned by the Quadrant backend.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuth2Response {
    /// Access token used for authenticated requests.
    pub access_token: String,
    /// Token type, typically `Bearer`.
    pub token_type: String,
    /// Access token lifetime in seconds.
    pub expires_in: i64,
    /// Optional refresh token.
    pub refresh_token: Option<String>,
    /// Granted OAuth scopes.
    pub scope: String,
}

/// Description of a cloud modpack update pending local application.
#[derive(Debug, Clone)]
pub struct PendingModpackUpdate {
    /// Remote synced modpack metadata.
    pub synced_modpack: SyncedModpack,
    /// Matching local modpack name.
    pub local_name: String,
    /// Matching local modpack version.
    pub local_version: String,
    /// Local sync time in seconds since the Unix epoch.
    pub local_sync_time: i64,
}

/// Uses the refresh token to obtain and persist a fresh access token.
pub async fn try_refresh_token(
    secret_store: &impl SecretStore,
    client_id: &str,
    client_secret: &str,
    user_agent: &str,
) -> Result<()> {
    let refresh_token = get_refresh_token(secret_store)?;
    let mut body = HashMap::new();
    body.insert("client_id", client_id);
    body.insert("client_secret", client_secret);
    body.insert("grant_type", "refresh_token");
    body.insert("refresh_token", refresh_token.as_str());

    let response = reqwest::Client::new()
        .post(format!("{}/oauth2/token", QNT_BASE_URL))
        .form(&body)
        .header("User-Agent", user_agent)
        .send()
        .await?;

    if !response.status().is_success() {
        return Err(anyhow::anyhow!(
            "Token refresh failed: {}",
            response.status()
        ));
    }

    let res = response.json::<OAuth2Response>().await?;
    set_secret(secret_store, "accountToken", &res.access_token)?;
    if let Some(new_refresh_token) = res.refresh_token {
        set_secret(secret_store, "refreshToken", &new_refresh_token)?;
    }
    Ok(())
}

/// Fetches the current account profile using the stored access token.
pub async fn get_account_info(
    secret_store: &impl SecretStore,
    user_agent: &str,
) -> Result<AccountInfo> {
    let token = get_account_token(secret_store)?;
    let client = reqwest::Client::new();
    let url = format!("{}/account/info/get", QNT_BASE_URL);

    let response = client
        .get(&url)
        .header("User-Agent", user_agent)
        .bearer_auth(&token)
        .send()
        .await?;

    let response_raw = response.text().await?;
    Ok(serde_json::from_str(&response_raw)?)
}

/// Fetches account info and attempts a token refresh if the request is unauthorized.
pub async fn get_account_info_with_refresh(
    secret_store: &impl SecretStore,
    user_agent: &str,
    client_id: &str,
    client_secret: &str,
) -> Result<AccountInfo> {
    let token = get_account_token(secret_store)?;
    let client = reqwest::Client::new();
    let url = format!("{}/account/info/get", QNT_BASE_URL);

    let response = client
        .get(&url)
        .header("User-Agent", user_agent)
        .bearer_auth(&token)
        .send()
        .await?;

    if response.status() == StatusCode::UNAUTHORIZED {
        try_refresh_token(secret_store, client_id, client_secret, user_agent).await?;
        let new_token = get_account_token(secret_store)?;
        let retry = client
            .get(&url)
            .header("User-Agent", user_agent)
            .bearer_auth(&new_token)
            .send()
            .await?;
        let raw = retry.text().await?;
        return Ok(serde_json::from_str(&raw)?);
    }

    let response_raw = response.text().await?;
    Ok(serde_json::from_str(&response_raw)?)
}

/// Completes the OAuth authorization code flow and persists returned tokens.
pub async fn oauth2_login(
    secret_store: &impl SecretStore,
    user_agent: &str,
    client_id: &str,
    client_secret: &str,
    code: String,
    redirect_uri: String,
) -> Result<()> {
    let mut body = HashMap::new();
    body.insert("client_id", client_id);
    body.insert("client_secret", client_secret);
    body.insert("grant_type", "authorization_code");
    body.insert("code", code.as_str());
    body.insert("redirect_uri", redirect_uri.as_str());

    let response = reqwest::Client::new()
        .post(format!("{}/oauth2/token", QNT_BASE_URL))
        .form(&body)
        .header("User-Agent", user_agent)
        .send()
        .await?;

    let res = response.text().await?;
    let res = serde_json::from_str::<OAuth2Response>(&res)?;
    if !res.scope.contains("profile:read")
        || !res.scope.contains("sync:read")
        || !res.scope.contains("notifications:read")
    {
        return Err(anyhow::anyhow!("Invalid scope"));
    }
    set_secret(secret_store, "accountToken", &res.access_token)?;
    if let Some(refresh_token) = res.refresh_token {
        set_secret(secret_store, "refreshToken", &refresh_token)?;
    }
    Ok(())
}

/// Marks a notification as read in the Quadrant backend.
pub async fn read_notification(
    secret_store: &impl SecretStore,
    user_agent: &str,
    notification_id: String,
) -> Result<()> {
    let token = get_account_token(secret_store)?;
    let request = reqwest::Client::new()
        .post(format!("{}/account/notifications/read", QNT_BASE_URL))
        .header("User-Agent", user_agent)
        .bearer_auth(&token)
        .json(&serde_json::json!({
            "notification_id": notification_id,
        }))
        .send()
        .await?;

    if request.status() != 200 {
        let body = request.text().await?;
        return Err(anyhow::anyhow!(body));
    }
    Ok(())
}

/// Compares local and remote sync timestamps to find pending cloud updates.
pub fn determine_pending_modpack_updates(
    local_modpacks: &[crate::models::LocalModpack],
    synced_modpacks: &[SyncedModpack],
    updated_modpacks: &[String],
) -> Vec<PendingModpackUpdate> {
    let mut pending = Vec::new();
    for modpack in local_modpacks {
        if modpack.last_synced == 0 {
            continue;
        }
        for matching_modpack in synced_modpacks.iter().filter(|m| m.name == modpack.name) {
            let cloud_sync_time = matching_modpack.last_synced;
            let local_sync_time = modpack.last_synced / 1000;
            let is_updated = updated_modpacks.contains(&modpack.name);
            let is_older = cloud_sync_time <= local_sync_time;
            if is_older || is_updated {
                continue;
            }
            pending.push(PendingModpackUpdate {
                synced_modpack: matching_modpack.clone(),
                local_name: modpack.name.clone(),
                local_version: modpack.version.clone(),
                local_sync_time,
            });
        }
    }
    pending
}
