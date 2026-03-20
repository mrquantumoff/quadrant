//! Account identity, login, refresh, and notification APIs.

use std::{collections::HashMap, env};

use reqwest::StatusCode;
use serde::{Deserialize, Serialize};

use crate::{
    Result,
    account::{QNT_BASE_URL, get_account_token, get_refresh_token, set_secret},
    ports::SecretStore,
};

use super::quadrant_sync::SyncedModpack;

const DEFAULT_NOTIFICATION_HISTORY_LIMIT: usize = 500;
const DEFAULT_NOTIFICATION_HISTORY_SINCE: &str = "1970-01-01T00:00:00Z";

fn backend_base_url() -> String {
    env::var("QUADRANT_API_BASE_URL").unwrap_or_else(|_| QNT_BASE_URL.to_string())
}

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
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Notification {
    /// Stable notification identifier.
    pub notification_id: String,
    /// Owning user identifier.
    pub user_id: String,
    /// Human-readable notification message as a JSON string.
    pub message: String,
    /// RFC3339 creation timestamp.
    pub created_at: String,
    /// Creation timestamp in seconds since the Unix epoch.
    pub created_at_unix: i64,
    /// Whether the notification has been marked as read.
    pub read: bool,
}

/// Paginated notification history response.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct NotificationHistoryResponse {
    pub notifications: Vec<Notification>,
    pub has_more: bool,
    pub next_since: Option<String>,
    pub next_after_id: Option<String>,
}

/// Persisted notification cursor.
#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq, Eq)]
pub struct NotificationCursor {
    pub created_at: Option<String>,
    pub notification_id: Option<String>,
}

/// WebSocket frame emitted by the notification backend.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum NotificationWsFrame {
    Connected {
        server_time: String,
    },
    Notification {
        delivery: String,
        notification: Notification,
    },
    ReplayComplete {
        count: usize,
        truncated: bool,
    },
    Error {
        error: String,
    },
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
    log::info!("Attempting token refresh");
    let refresh_token = get_refresh_token(secret_store)?;
    let mut body = HashMap::new();
    body.insert("client_id", client_id);
    body.insert("client_secret", client_secret);
    body.insert("grant_type", "refresh_token");
    body.insert("refresh_token", refresh_token.as_str());

    let response = reqwest::Client::new()
        .post(format!("{}/oauth2/token", backend_base_url()))
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
    log::info!("Token refresh successful");
    Ok(())
}

/// Fetches the current account profile using the stored access token.
pub async fn get_account_info(
    secret_store: &impl SecretStore,
    user_agent: &str,
) -> Result<AccountInfo> {
    log::info!("Fetching account info");
    let token = get_account_token(secret_store)?;
    let client = reqwest::Client::new();
    let url = format!("{}/account/info/get", backend_base_url());

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
    let url = format!("{}/account/info/get", backend_base_url());

    let response = client
        .get(&url)
        .header("User-Agent", user_agent)
        .bearer_auth(&token)
        .send()
        .await?;

    if response.status() == StatusCode::UNAUTHORIZED {
        log::info!("Account info request unauthorized, attempting token refresh");
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
    log::info!("Starting OAuth2 login flow");
    let mut body = HashMap::new();
    body.insert("client_id", client_id);
    body.insert("client_secret", client_secret);
    body.insert("grant_type", "authorization_code");
    body.insert("code", code.as_str());
    body.insert("redirect_uri", redirect_uri.as_str());

    let response = reqwest::Client::new()
        .post(format!("{}/oauth2/token", backend_base_url()))
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
    log::info!("OAuth2 login successful");
    Ok(())
}

/// Fetches a single page of notification history from the Quadrant backend.
pub async fn get_notification_history_page(
    secret_store: &impl SecretStore,
    user_agent: &str,
    cursor: Option<&NotificationCursor>,
    read: Option<bool>,
    limit: Option<usize>,
) -> Result<NotificationHistoryResponse> {
    let token = get_account_token(secret_store)?;
    let cursor = cursor.cloned().unwrap_or_default();
    let limit = limit
        .unwrap_or(DEFAULT_NOTIFICATION_HISTORY_LIMIT)
        .min(DEFAULT_NOTIFICATION_HISTORY_LIMIT);
    let since = cursor
        .created_at
        .unwrap_or_else(|| DEFAULT_NOTIFICATION_HISTORY_SINCE.to_string());
    let mut query = vec![
        ("since".to_string(), since),
        ("limit".to_string(), limit.to_string()),
    ];
    if let Some(after_id) = cursor.notification_id {
        query.push(("after_id".to_string(), after_id));
    }
    if let Some(read) = read {
        query.push(("read".to_string(), read.to_string()));
    }

    let response = reqwest::Client::new()
        .get(format!("{}/account/notifications/get", backend_base_url()))
        .header("User-Agent", user_agent)
        .bearer_auth(token)
        .query(&query)
        .send()
        .await?;

    let response_raw = response.text().await?;
    Ok(serde_json::from_str(&response_raw)?)
}

/// Fetches all notification history pages from the provided cursor onward.
pub async fn get_notification_history_all_since(
    secret_store: &impl SecretStore,
    user_agent: &str,
    cursor: Option<&NotificationCursor>,
    read: Option<bool>,
) -> Result<(Vec<Notification>, NotificationCursor)> {
    let mut page_cursor = cursor.cloned().unwrap_or_default();
    let mut notifications = Vec::new();

    loop {
        let page = get_notification_history_page(
            secret_store,
            user_agent,
            Some(&page_cursor),
            read,
            Some(DEFAULT_NOTIFICATION_HISTORY_LIMIT),
        )
        .await?;

        if let Some(last) = page.notifications.last() {
            page_cursor = NotificationCursor {
                created_at: Some(last.created_at.clone()),
                notification_id: Some(last.notification_id.clone()),
            };
        }
        notifications.extend(page.notifications);

        if !page.has_more {
            break;
        }

        page_cursor.created_at = page.next_since.or(page_cursor.created_at);
        page_cursor.notification_id = page.next_after_id.or(page_cursor.notification_id);
    }

    Ok((notifications, page_cursor))
}

/// Marks a notification as read in the Quadrant backend.
pub async fn read_notification(
    secret_store: &impl SecretStore,
    user_agent: &str,
    notification_id: String,
) -> Result<()> {
    log::info!("Marking notification {notification_id} as read");
    let token = get_account_token(secret_store)?;
    let request = reqwest::Client::new()
        .post(format!("{}/account/notifications/read", backend_base_url()))
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
    log::info!("Determining pending modpack updates");
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
    log::info!("Found {} pending modpack update(s)", pending.len());
    pending
}

#[cfg(test)]
mod tests {
    use super::{
        Notification, NotificationCursor, NotificationWsFrame, get_notification_history_all_since,
        get_notification_history_page,
    };
    use crate::{Result, ports::SecretStore};
    use httpmock::{Method::GET, MockServer};
    use std::sync::Mutex;

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    struct MemorySecretStore;

    impl SecretStore for MemorySecretStore {
        fn get_secret(&self, key: &str) -> Result<Option<String>> {
            match key {
                "accountToken" => Ok(Some("token-123".to_string())),
                _ => Ok(None),
            }
        }

        fn set_secret(&self, _key: &str, _value: &str) -> Result<()> {
            Ok(())
        }

        fn delete_secret(&self, _key: &str) -> Result<()> {
            Ok(())
        }
    }

    fn notification(id: &str, ts: &str, unix: i64) -> Notification {
        Notification {
            notification_id: id.to_string(),
            user_id: "user-1".to_string(),
            message: "{\"simple_message\":\"hi\"}".to_string(),
            created_at: ts.to_string(),
            created_at_unix: unix,
            read: false,
        }
    }

    #[tokio::test]
    async fn notification_history_page_uses_cursor_query() {
        let _guard = ENV_LOCK.lock().unwrap();
        let server = MockServer::start();
        unsafe {
            std::env::set_var("QUADRANT_API_BASE_URL", server.base_url());
        }

        let _mock = server.mock(|when, then| {
            when.method(GET)
                .path("/account/notifications/get")
                .header("authorization", "Bearer token-123")
                .query_param("since", "2026-03-20T00:00:00Z")
                .query_param("after_id", "cursor-1")
                .query_param("limit", "500");
            then.status(200).json_body_obj(&serde_json::json!({
                "notifications": [],
                "has_more": false,
                "next_since": null,
                "next_after_id": null
            }));
        });

        let response = get_notification_history_page(
            &MemorySecretStore,
            "test-agent",
            Some(&NotificationCursor {
                created_at: Some("2026-03-20T00:00:00Z".to_string()),
                notification_id: Some("cursor-1".to_string()),
            }),
            None,
            Some(999),
        )
        .await
        .unwrap();

        assert!(response.notifications.is_empty());
    }

    #[tokio::test]
    async fn notification_history_all_since_follows_pagination() {
        let _guard = ENV_LOCK.lock().unwrap();
        let server = MockServer::start();
        unsafe {
            std::env::set_var("QUADRANT_API_BASE_URL", server.base_url());
        }

        let _page_one = server.mock(|when, then| {
            when.method(GET)
                .path("/account/notifications/get")
                .query_param("since", "2026-03-20T00:00:00Z")
                .query_param("limit", "500");
            then.status(200).json_body_obj(&serde_json::json!({
                "notifications": [notification("n1", "2026-03-20T10:00:00Z", 1)],
                "has_more": true,
                "next_since": "2026-03-20T10:00:00Z",
                "next_after_id": "n1"
            }));
        });

        let _page_two = server.mock(|when, then| {
            when.method(GET)
                .path("/account/notifications/get")
                .query_param("since", "2026-03-20T10:00:00Z")
                .query_param("after_id", "n1")
                .query_param("limit", "500");
            then.status(200).json_body_obj(&serde_json::json!({
                "notifications": [notification("n2", "2026-03-20T10:15:30.123Z", 2)],
                "has_more": false,
                "next_since": "2026-03-20T10:15:30.123Z",
                "next_after_id": "n2"
            }));
        });

        let (notifications, cursor) = get_notification_history_all_since(
            &MemorySecretStore,
            "test-agent",
            Some(&NotificationCursor {
                created_at: Some("2026-03-20T00:00:00Z".to_string()),
                notification_id: None,
            }),
            None,
        )
        .await
        .unwrap();

        assert_eq!(notifications.len(), 2);
        assert_eq!(
            cursor.created_at.as_deref(),
            Some("2026-03-20T10:15:30.123Z")
        );
        assert_eq!(cursor.notification_id.as_deref(), Some("n2"));
    }

    #[test]
    fn websocket_frames_deserialize() {
        let connected: NotificationWsFrame = serde_json::from_str(
            r#"{"event":"connected","server_time":"2026-03-20T10:20:00.000Z"}"#,
        )
        .unwrap();
        assert!(matches!(connected, NotificationWsFrame::Connected { .. }));

        let replay: NotificationWsFrame = serde_json::from_str(
            r#"{"event":"notification","delivery":"replay","notification":{"notification_id":"n1","user_id":"u1","message":"{\"simple_message\":\"x\"}","created_at":"2026-03-20T10:15:30.123Z","created_at_unix":1774001730,"read":false}}"#,
        )
        .unwrap();
        assert!(matches!(replay, NotificationWsFrame::Notification { .. }));

        let replay_complete: NotificationWsFrame =
            serde_json::from_str(r#"{"event":"replay_complete","count":100,"truncated":true}"#)
                .unwrap();
        assert!(matches!(
            replay_complete,
            NotificationWsFrame::ReplayComplete {
                truncated: true,
                ..
            }
        ));

        let error: NotificationWsFrame =
            serde_json::from_str(r#"{"event":"error","error":"lagged"}"#).unwrap();
        assert!(matches!(error, NotificationWsFrame::Error { .. }));
    }
}
