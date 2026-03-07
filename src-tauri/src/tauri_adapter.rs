use std::path::{Path, PathBuf};

use anyhow::anyhow;
use keyring::Entry;
use quadrant_core::{
    Result,
    events::BackendEvent,
    ports::{EventSink, Notifier, RuntimeState, SecretStore, SettingsStore, Shell},
};
use serde_json::Value;
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_dialog::DialogExt;
use tauri_plugin_notification::NotificationExt;
use tauri_plugin_store::StoreExt;
use tokio::sync::Mutex;

use crate::AppState;

#[derive(Clone)]
pub struct TauriSettingsStore {
    app: AppHandle,
    store_name: &'static str,
}

impl TauriSettingsStore {
    pub fn new(app: AppHandle, store_name: &'static str) -> Self {
        Self { app, store_name }
    }
}

impl SettingsStore for TauriSettingsStore {
    fn get_value(&self, key: &str) -> Result<Option<Value>> {
        let store = self
            .app
            .store(self.store_name)
            .map_err(anyhow::Error::from)?;
        Ok(store.get(key))
    }

    fn set_value(&self, key: &str, value: Value) -> Result<()> {
        let store = self
            .app
            .store(self.store_name)
            .map_err(anyhow::Error::from)?;
        store.set(key, value);
        Ok(())
    }
}

#[derive(Clone)]
pub struct TauriEventSink {
    app: AppHandle,
}

impl TauriEventSink {
    pub fn new(app: AppHandle) -> Self {
        Self { app }
    }
}

impl EventSink for TauriEventSink {
    fn publish(&self, event: BackendEvent) -> Result<()> {
        match event {
            BackendEvent::ModDownloadProgress(payload) => {
                self.app.emit("modDownloadProgress", payload)?;
            }
            BackendEvent::ModInstallProgress(payload) => {
                self.app.emit("modInstallProgress", payload)?;
            }
            BackendEvent::ModpackDownloadProgress(progress) => {
                self.app.emit("modpackDownloadProgress", progress)?;
            }
            BackendEvent::QuadrantExportProgress(progress) => {
                self.app.emit("quadrantExportProgress", progress)?;
            }
            BackendEvent::QuadrantShareSubmission(payload) => {
                self.app.emit("quadrantShareSubmission", payload)?;
            }
            BackendEvent::RefreshNotifications(payload) => {
                self.app.emit("refreshNotifications", payload)?;
            }
            BackendEvent::RecheckAccountToken => {
                self.app.emit("recheckAccountToken", "")?;
            }
        }
        Ok(())
    }
}

pub struct TauriSecretStore;

impl SecretStore for TauriSecretStore {
    fn get_secret(&self, key: &str) -> Result<Option<String>> {
        let entry = Entry::new("dev.mrquantumoff.mcmodpackmanager", key)?;
        match entry.get_password() {
            Ok(value) => Ok(Some(value)),
            Err(_) => Ok(None),
        }
    }

    fn set_secret(&self, key: &str, value: &str) -> Result<()> {
        let entry = Entry::new("dev.mrquantumoff.mcmodpackmanager", key)?;
        entry.set_password(value)?;
        Ok(())
    }

    fn delete_secret(&self, key: &str) -> Result<()> {
        let entry = Entry::new("dev.mrquantumoff.mcmodpackmanager", key)?;
        entry.delete_credential()?;
        Ok(())
    }
}

#[derive(Clone)]
pub struct TauriShell {
    app: AppHandle,
}

impl TauriShell {
    pub fn new(app: AppHandle) -> Self {
        Self { app }
    }
}

impl Shell for TauriShell {
    fn open_url(&self, url: &str) -> Result<()> {
        open::that_detached(url).map_err(anyhow::Error::from)
    }

    fn open_path(&self, path: &Path) -> Result<()> {
        open::that_detached(path).map_err(anyhow::Error::from)
    }

    fn choose_export_path(&self, suggested_name: &str) -> Result<Option<PathBuf>> {
        let selected = self
            .app
            .dialog()
            .file()
            .add_filter("Quadrant Export", &["quadrantExport.zip"])
            .set_file_name(suggested_name)
            .blocking_save_file();
        Ok(selected.and_then(|file| file.into_path().ok()))
    }
}

#[derive(Clone)]
pub struct TauriNotifier {
    app: AppHandle,
}

impl TauriNotifier {
    pub fn new(app: AppHandle) -> Self {
        Self { app }
    }
}

impl Notifier for TauriNotifier {
    fn notify(&self, title: &str, body: &str) -> Result<()> {
        self.app
            .notification()
            .builder()
            .title(title)
            .body(body)
            .show()
            .map_err(anyhow::Error::from)?;
        Ok(())
    }
}

#[derive(Clone)]
pub struct TauriRuntimeState {
    app: AppHandle,
}

impl TauriRuntimeState {
    pub fn new(app: AppHandle) -> Self {
        Self { app }
    }
}

impl RuntimeState for TauriRuntimeState {
    fn get_value(&self, key: &str) -> Result<Option<Value>> {
        let state = self.app.state::<Mutex<AppState>>();
        let state = state
            .try_lock()
            .map_err(|_| anyhow!("runtime state is busy"))?;
        match key {
            "is_update_enabled" => Ok(Some(Value::Bool(state.is_update_enabled))),
            "updated_modpacks" => Ok(Some(serde_json::to_value(&state.updated_modpacks)?)),
            _ => Ok(None),
        }
    }

    fn set_value(&self, key: &str, value: Value) -> Result<()> {
        let state = self.app.state::<Mutex<AppState>>();
        let mut state = state
            .try_lock()
            .map_err(|_| anyhow!("runtime state is busy"))?;
        match key {
            "is_update_enabled" => {
                state.is_update_enabled = value.as_bool().unwrap_or(false);
            }
            "updated_modpacks" => {
                state.updated_modpacks = serde_json::from_value(value)?;
            }
            _ => {}
        }
        Ok(())
    }
}

pub fn mc_folder(app: &AppHandle) -> Result<PathBuf> {
    let store = app.store("config.json").map_err(anyhow::Error::from)?;
    let mc_folder = store
        .get("mcFolder")
        .and_then(|value| value.as_str().map(PathBuf::from))
        .ok_or_else(|| anyhow!("mcFolder is not configured"))?;
    Ok(mc_folder)
}
