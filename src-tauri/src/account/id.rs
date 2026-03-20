use std::{collections::HashMap, path::PathBuf, time::Duration};

use anyhow::anyhow;
use futures::StreamExt;
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_notification::NotificationExt;
use tauri_plugin_store::StoreExt;
use tokio::sync::Mutex;
use tokio_tungstenite::{
    connect_async,
    tungstenite::{Message, client::IntoClientRequest},
};
use url::Url;

use crate::{
    AppState,
    account::{
        self,
        quadrant_settings_sync::{get_quadrant_settings, submit_quadrant_settings},
        quadrant_sync::get_synced_modpacks,
    },
    mc_mod::get_user_agent,
    modpacks::general::{InstalledModpack, get_modpacks, install_modpack},
    tauri_adapter::TauriSecretStore,
};

pub use quadrant_core::account::id::{
    AccountInfo, Notification, NotificationCursor, NotificationWsFrame, OAuth2Response,
};

const NOTIFICATION_CURSOR_CREATED_AT_KEY: &str = "notificationCursorCreatedAt";
const NOTIFICATION_CURSOR_NOTIFICATION_ID_KEY: &str = "notificationCursorNotificationId";
const SHOWN_NOTIFICATIONS_KEY: &str = "shownNotifications";
const MODPACK_SYNC_INTERVAL_SECS: u64 = 60;
const SETTINGS_SYNC_INTERVAL_SECS: u64 = 120;
const WS_REPLAY_LIMIT: usize = 500;
const NOTIFICATION_TITLE: &str = "Quadrant ID";

#[derive(Default, Clone)]
pub struct NotificationRuntimeState {
    pub by_id: HashMap<String, Notification>,
    pub ordered_ids: Vec<String>,
    pub cursor: NotificationCursor,
    pub reconnect_attempt: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct UpsertOutcome {
    changed: bool,
    inserted: bool,
}

impl NotificationRuntimeState {
    fn merge(&mut self, notifications: Vec<Notification>) -> bool {
        let mut changed = false;
        for notification in notifications {
            changed |= self.upsert(notification).changed;
        }
        changed
    }

    fn upsert(&mut self, notification: Notification) -> UpsertOutcome {
        self.advance_cursor(&notification);
        match self.by_id.get(&notification.notification_id) {
            Some(existing) if existing == &notification => UpsertOutcome {
                changed: false,
                inserted: false,
            },
            Some(_) => {
                self.by_id
                    .insert(notification.notification_id.clone(), notification);
                self.sort_ids();
                UpsertOutcome {
                    changed: true,
                    inserted: false,
                }
            }
            None => {
                self.ordered_ids.push(notification.notification_id.clone());
                self.by_id
                    .insert(notification.notification_id.clone(), notification);
                self.sort_ids();
                UpsertOutcome {
                    changed: true,
                    inserted: true,
                }
            }
        }
    }

    fn mark_read(&mut self, notification_id: &str) -> bool {
        let Some(notification) = self.by_id.get_mut(notification_id) else {
            return false;
        };
        if notification.read {
            return false;
        }
        notification.read = true;
        true
    }

    fn notifications_for_ui(&self) -> Vec<Notification> {
        let mut notifications = self
            .ordered_ids
            .iter()
            .filter_map(|id| self.by_id.get(id))
            .cloned()
            .collect::<Vec<_>>();
        notifications.sort_by(|a, b| {
            b.created_at_unix
                .cmp(&a.created_at_unix)
                .then_with(|| b.notification_id.cmp(&a.notification_id))
        });
        notifications
    }

    fn advance_cursor(&mut self, notification: &Notification) {
        let current_created_at = self.cursor.created_at.as_deref();
        let current_notification_id = self.cursor.notification_id.as_deref();
        let is_newer = match current_created_at {
            None => true,
            Some(created_at) => {
                notification.created_at.as_str() > created_at
                    || (notification.created_at.as_str() == created_at
                        && current_notification_id
                            .map(|id| notification.notification_id.as_str() > id)
                            .unwrap_or(true))
            }
        };

        if is_newer {
            self.cursor = NotificationCursor {
                created_at: Some(notification.created_at.clone()),
                notification_id: Some(notification.notification_id.clone()),
            };
        }
    }

    fn sort_ids(&mut self) {
        self.ordered_ids.sort_by(|left, right| {
            let left_notification = self.by_id.get(left).expect("missing notification");
            let right_notification = self.by_id.get(right).expect("missing notification");
            left_notification
                .created_at_unix
                .cmp(&right_notification.created_at_unix)
                .then_with(|| {
                    left_notification
                        .notification_id
                        .cmp(&right_notification.notification_id)
                })
        });
    }
}

#[tauri::command]
pub async fn get_account_info() -> Result<AccountInfo, tauri::Error> {
    quadrant_core::account::id::get_account_info_with_refresh(
        &TauriSecretStore,
        &get_user_agent(),
        env!("QUADRANT_OAUTH2_CLIENT_ID"),
        env!("QUADRANT_OAUTH2_CLIENT_SECRET"),
    )
    .await
    .map_err(tauri::Error::from)
}

#[tauri::command]
pub async fn oauth2_login(
    code: String,
    redirect_uri: String,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    quadrant_core::account::id::oauth2_login(
        &TauriSecretStore,
        &get_user_agent(),
        env!("QUADRANT_OAUTH2_CLIENT_ID"),
        env!("QUADRANT_OAUTH2_CLIENT_SECRET"),
        code,
        redirect_uri,
    )
    .await
    .map_err(tauri::Error::from)?;
    app.emit("recheckAccountToken", "")?;
    Ok(())
}

#[tauri::command]
pub fn oauth2_client_id() -> String {
    env!("QUADRANT_OAUTH2_CLIENT_ID").to_string()
}

#[tauri::command]
pub async fn read_notification(
    notification_id: String,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    quadrant_core::account::id::read_notification(
        &TauriSecretStore,
        &get_user_agent(),
        notification_id.clone(),
    )
    .await
    .map_err(tauri::Error::from)?;

    if let Some(notifications) = mark_notification_read_and_snapshot(&app, &notification_id).await {
        emit_notification_refresh(&app, notifications)?;
    }

    Ok(())
}

pub fn start_notification_worker(app: AppHandle) {
    tokio::task::spawn(async move {
        loop {
            if let Err(error) = bootstrap_notifications(&app).await {
                log::warn!("Notification bootstrap failed: {error}");
            }

            let stream_result = run_notification_socket(app.clone()).await;
            if let Err(error) = stream_result {
                log::warn!("Notification socket cycle ended: {error}");
            }

            if let Err(error) = bootstrap_notifications(&app).await {
                log::warn!("Notification catch-up failed after socket cycle: {error}");
            }

            let delay = {
                let state = app.state::<Mutex<AppState>>();
                let mut state = state.lock().await;
                state.notification_state.reconnect_attempt =
                    state.notification_state.reconnect_attempt.saturating_add(1);
                reconnect_delay(state.notification_state.reconnect_attempt)
            };
            tokio::time::sleep(delay).await;
        }
    });
}

pub fn start_modpack_sync_worker(app: AppHandle) {
    tokio::task::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(MODPACK_SYNC_INTERVAL_SECS));
        loop {
            interval.tick().await;
            if let Err(error) = sync_modpack_updates(app.clone()).await {
                log::warn!("Modpack sync worker failed: {error}");
            }
        }
    });
}

pub fn start_settings_sync_worker(app: AppHandle) {
    tokio::task::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(SETTINGS_SYNC_INTERVAL_SECS));
        loop {
            interval.tick().await;
            if let Err(error) = sync_remote_settings(app.clone()).await {
                log::warn!("Settings sync worker failed: {error}");
            }
        }
    });
}

async fn bootstrap_notifications(app: &AppHandle) -> Result<(), anyhow::Error> {
    let cursor = load_notification_cursor(app)?;
    let (notifications, next_cursor) =
        quadrant_core::account::id::get_notification_history_all_since(
            &TauriSecretStore,
            &get_user_agent(),
            Some(&cursor),
            None,
        )
        .await?;

    if notifications.is_empty() && next_cursor == cursor {
        return Ok(());
    }

    let notifications_to_emit = {
        let state = app.state::<Mutex<AppState>>();
        let mut state = state.lock().await;
        let runtime = &mut state.notification_state;
        let changed = runtime.merge(notifications);
        if runtime.cursor != next_cursor {
            runtime.cursor = next_cursor.clone();
        }
        changed.then(|| runtime.notifications_for_ui())
    };

    persist_notification_cursor(app, &next_cursor)?;

    if let Some(notifications) = notifications_to_emit {
        emit_notification_refresh(app, notifications)?;
    }

    set_reconnect_attempt(app, 0).await;

    Ok(())
}

async fn run_notification_socket(app: AppHandle) -> Result<(), anyhow::Error> {
    let token = account::get_account_token()?;
    let cursor = {
        let state = app.state::<Mutex<AppState>>();
        let state = state.lock().await;
        state.notification_state.cursor.clone()
    };

    let ws_url = build_notification_ws_url(&cursor)?;
    let mut request = ws_url.as_str().into_client_request()?;
    request
        .headers_mut()
        .insert("Authorization", format!("Bearer {token}").parse()?);
    request
        .headers_mut()
        .insert("User-Agent", get_user_agent().parse()?);

    let (mut socket, _) = connect_async(request).await?;
    set_reconnect_attempt(&app, 0).await;

    while let Some(frame) = socket.next().await {
        match frame? {
            Message::Text(payload) => {
                let payload = payload.to_string();
                handle_notification_ws_frame(&app, &payload).await?;
            }
            Message::Close(frame) => {
                let reason = frame
                    .map(|f| f.reason.to_string())
                    .unwrap_or_else(|| "closed".to_string());
                return Err(anyhow!("notification websocket closed: {reason}"));
            }
            Message::Ping(_) | Message::Pong(_) | Message::Binary(_) | Message::Frame(_) => {}
        }
    }

    Err(anyhow!("notification websocket stream ended"))
}

async fn handle_notification_ws_frame(app: &AppHandle, payload: &str) -> Result<(), anyhow::Error> {
    let frame = serde_json::from_str::<NotificationWsFrame>(payload)?;
    match frame {
        NotificationWsFrame::Connected { server_time } => {
            log::info!("Notification websocket connected at {server_time}");
        }
        NotificationWsFrame::Notification {
            delivery,
            notification,
        } => {
            let should_notify = delivery == "live" && !notification.read;
            let notification_id = notification.notification_id.clone();
            let simple_message = notification_simple_message(&notification);

            let notifications_to_emit = {
                let state = app.state::<Mutex<AppState>>();
                let mut state = state.lock().await;
                let outcome = state.notification_state.upsert(notification);
                outcome.changed.then(|| {
                    (
                        state.notification_state.notifications_for_ui(),
                        outcome.inserted,
                    )
                })
            };

            if let Some((notifications, inserted)) = notifications_to_emit {
                emit_notification_refresh(app, notifications)?;
                if should_notify && inserted {
                    maybe_show_native_notification(
                        app,
                        &notification_id,
                        simple_message.as_deref(),
                    )
                    .await?;
                }
            }
        }
        NotificationWsFrame::ReplayComplete { truncated, .. } => {
            if truncated {
                bootstrap_notifications(app).await?;
            }
        }
        NotificationWsFrame::Error { error } => {
            if error.to_lowercase().contains("lagged") {
                bootstrap_notifications(app).await?;
            }
            return Err(anyhow!("notification websocket error frame: {error}"));
        }
    }

    Ok(())
}

fn build_notification_ws_url(cursor: &NotificationCursor) -> Result<Url, anyhow::Error> {
    let base = std::env::var("QUADRANT_API_BASE_URL")
        .unwrap_or_else(|_| quadrant_core::account::QNT_BASE_URL.to_string());
    let mut url = Url::parse(&base)?;
    match url.scheme() {
        "https" => url
            .set_scheme("wss")
            .map_err(|_| anyhow!("invalid ws scheme"))?,
        "http" => url
            .set_scheme("ws")
            .map_err(|_| anyhow!("invalid ws scheme"))?,
        "wss" | "ws" => {}
        _ => return Err(anyhow!("unsupported backend scheme")),
    }
    url.set_path("/api/v3/account/notifications/ws");
    {
        let mut query = url.query_pairs_mut();
        if let Some(created_at) = cursor.created_at.as_deref() {
            query.append_pair("since", created_at);
        }
        query.append_pair("replay_limit", &WS_REPLAY_LIMIT.to_string());
    }
    Ok(url)
}

fn reconnect_delay(attempt: u32) -> Duration {
    let secs = match attempt {
        0 => 1,
        1 => 1,
        2 => 2,
        3 => 5,
        4 => 10,
        5 => 30,
        _ => 60,
    };
    Duration::from_secs(secs)
}

fn emit_notification_refresh(
    app: &AppHandle,
    notifications: Vec<Notification>,
) -> Result<(), anyhow::Error> {
    app.emit("refreshNotifications", notifications)?;
    Ok(())
}

async fn mark_notification_read_and_snapshot(
    app: &AppHandle,
    notification_id: &str,
) -> Option<Vec<Notification>> {
    let state = app.state::<Mutex<AppState>>();
    let mut state = state.lock().await;
    state
        .notification_state
        .mark_read(notification_id)
        .then(|| state.notification_state.notifications_for_ui())
}

async fn set_reconnect_attempt(app: &AppHandle, attempt: u32) {
    let state = app.state::<Mutex<AppState>>();
    let mut state = state.lock().await;
    state.notification_state.reconnect_attempt = attempt;
}

fn load_notification_cursor(app: &AppHandle) -> Result<NotificationCursor, anyhow::Error> {
    let store = app.store("config.json")?;
    Ok(NotificationCursor {
        created_at: store
            .get(NOTIFICATION_CURSOR_CREATED_AT_KEY)
            .and_then(|value| value.as_str().map(ToOwned::to_owned)),
        notification_id: store
            .get(NOTIFICATION_CURSOR_NOTIFICATION_ID_KEY)
            .and_then(|value| value.as_str().map(ToOwned::to_owned)),
    })
}

fn persist_notification_cursor(
    app: &AppHandle,
    cursor: &NotificationCursor,
) -> Result<(), anyhow::Error> {
    let store = app.store("config.json")?;
    match &cursor.created_at {
        Some(created_at) => {
            store.set(
                NOTIFICATION_CURSOR_CREATED_AT_KEY,
                serde_json::Value::String(created_at.clone()),
            );
        }
        None => {
            store.delete(NOTIFICATION_CURSOR_CREATED_AT_KEY);
        }
    };
    match &cursor.notification_id {
        Some(notification_id) => {
            store.set(
                NOTIFICATION_CURSOR_NOTIFICATION_ID_KEY,
                serde_json::Value::String(notification_id.clone()),
            );
        }
        None => {
            store.delete(NOTIFICATION_CURSOR_NOTIFICATION_ID_KEY);
        }
    };
    store.save()?;
    Ok(())
}

async fn maybe_show_native_notification(
    app: &AppHandle,
    notification_id: &str,
    body: Option<&str>,
) -> Result<(), anyhow::Error> {
    let body = match body {
        Some(body) if !body.is_empty() => body,
        _ => return Ok(()),
    };

    let store = app.store("config.json")?;
    let mut shown_notifications = store
        .get(SHOWN_NOTIFICATIONS_KEY)
        .and_then(|value| serde_json::from_value::<Vec<String>>(value).ok())
        .unwrap_or_default();
    if shown_notifications.iter().any(|id| id == notification_id) {
        return Ok(());
    }

    app.notification()
        .builder()
        .title(NOTIFICATION_TITLE)
        .body(body)
        .show()?;

    shown_notifications.push(notification_id.to_string());
    store.set(
        SHOWN_NOTIFICATIONS_KEY,
        serde_json::to_value(shown_notifications)?,
    );
    store.save()?;

    Ok(())
}

fn notification_simple_message(notification: &Notification) -> Option<String> {
    serde_json::from_str::<serde_json::Value>(&notification.message)
        .ok()
        .and_then(|message| {
            message
                .get("simple_message")
                .and_then(|value| value.as_str().map(ToOwned::to_owned))
        })
}

async fn sync_modpack_updates(app: AppHandle) -> Result<(), anyhow::Error> {
    let config = app.store("config.json")?;
    let auto_quadrant_sync = config
        .get("autoQuadrantSync")
        .and_then(|value| value.as_bool())
        .unwrap_or(false);
    if !auto_quadrant_sync {
        return Ok(());
    }

    let mc_folder = config
        .get("mcFolder")
        .and_then(|value| value.as_str().map(PathBuf::from))
        .ok_or_else(|| anyhow!("mcFolder not configured"))?;
    let modpacks_folder = mc_folder.join("modpacks");

    let modpacks = get_modpacks(true, app.clone()).await;
    let synced_modpacks = get_synced_modpacks(false, None).await?;
    let state = app.state::<Mutex<AppState>>();
    let currently_updated = {
        let state = state.lock().await;
        state.updated_modpacks.clone()
    };
    let pending = quadrant_core::account::id::determine_pending_modpack_updates(
        &modpacks,
        &synced_modpacks,
        &currently_updated,
    );

    for pending_update in pending {
        {
            let mut state_mutex = state.lock().await;
            if state_mutex
                .updated_modpacks
                .contains(&pending_update.local_name)
            {
                continue;
            }
            state_mutex
                .updated_modpacks
                .push(pending_update.local_name.clone());
        }

        app.notification()
            .builder()
            .title(pending_update.local_name.clone())
            .large_body(format!(
                "{} | {}",
                pending_update.local_name, pending_update.local_version
            ))
            .body("Updating...")
            .show()?;

        install_modpack(
            InstalledModpack {
                mod_loader: pending_update.synced_modpack.mod_loader,
                name: pending_update.synced_modpack.name.clone(),
                version: pending_update.synced_modpack.minecraft_version.clone(),
                mods: serde_json::from_str(&pending_update.synced_modpack.mods)?,
            },
            app.clone(),
        )
        .await?;

        std::fs::write(
            modpacks_folder
                .join(&pending_update.local_name)
                .join("quadrantSync.json"),
            serde_json::to_string_pretty(&serde_json::json!({
                "last_synced": pending_update.synced_modpack.last_synced,
            }))?,
        )?;

        app.notification()
            .builder()
            .large_body(format!(
                "{} | {}",
                pending_update.local_name, pending_update.local_version
            ))
            .title(pending_update.local_name.clone())
            .body("Successfully updated!")
            .show()?;

        let mut state_mutex = state.lock().await;
        state_mutex
            .updated_modpacks
            .retain(|name| name != &pending_update.local_name);
    }

    Ok(())
}

async fn sync_remote_settings(app: AppHandle) -> Result<(), anyhow::Error> {
    let config = app.store("config.json")?;
    let auto_settings_sync = config
        .get("syncSettings")
        .and_then(|value| value.as_bool())
        .unwrap_or(false);
    if !auto_settings_sync {
        return Ok(());
    }

    let res = get_quadrant_settings(app.clone()).await;
    if let Err(error) = res
        && error.to_string() == "Current settings are newer"
    {
        submit_quadrant_settings(app).await?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{Notification, NotificationCursor, NotificationRuntimeState};

    fn notification(id: &str, unix: i64, read: bool) -> Notification {
        Notification {
            notification_id: id.to_string(),
            user_id: "u1".to_string(),
            message: "{\"simple_message\":\"hello\"}".to_string(),
            created_at: format!("2026-03-20T10:{unix:02}:00Z"),
            created_at_unix: unix,
            read,
        }
    }

    #[test]
    fn merge_notifications_deduplicates_and_orders() {
        let mut state = NotificationRuntimeState::default();
        assert!(state.merge(vec![
            notification("n1", 1, false),
            notification("n2", 2, false)
        ]));
        assert!(!state.merge(vec![notification("n1", 1, false)]));

        let notifications = state.notifications_for_ui();
        assert_eq!(notifications[0].notification_id, "n2");
        assert_eq!(notifications[1].notification_id, "n1");
        assert_eq!(
            state.cursor,
            NotificationCursor {
                created_at: Some("2026-03-20T10:02:00Z".to_string()),
                notification_id: Some("n2".to_string()),
            }
        );
    }

    #[test]
    fn mark_notification_read_local_updates_cached_notification() {
        let mut state = NotificationRuntimeState::default();
        state.merge(vec![notification("n1", 1, false)]);
        assert!(state.mark_read("n1"));
        assert!(state.by_id.get("n1").unwrap().read);
        assert!(!state.mark_read("n1"));
    }
}
