#[cfg(feature = "telemetry")]
pub mod telemetry;

pub mod rss;

#[tauri::command]
pub fn open_link(url: String) -> Result<(), tauri::Error> {
    open::that_detached(url).map_err(tauri::Error::from)
}
