use keyring::Entry;
pub mod id;
pub mod quadrant_settings_sync;
pub mod quadrant_share;
pub mod quadrant_sync;

pub(crate) const BASE_URL: &'static str = "https://api.mrquantumoff.dev/api/v3";

#[tauri::command]
pub fn set_secret(key: String, value: String) -> Result<(), tauri::Error> {
    let entry = Entry::new("dev.mrquantumoff.quadrant", &key)
        .map_err(|e| tauri::Error::from(anyhow::Error::from(e)))?;
    entry
        .set_password(&value)
        .map_err(|e| tauri::Error::from(anyhow::Error::from(e)))?;
    Ok(())
}

pub fn get_account_token() -> Result<String, anyhow::Error> {
    let entry = Entry::new("dev.mrquantumoff.mcmodpackmanager", "accountToken")?;
    entry.get_password().map_err(|e| e.into())
}

#[tauri::command]
pub fn clear_account_token() -> Result<(), tauri::Error> {
    let entry = Entry::new("dev.mrquantumoff.mcmodpackmanager", "accountToken")
        .map_err(|e| tauri::Error::from(anyhow::Error::from(e)))?;
    entry
        .delete_credential()
        .map_err(|e| tauri::Error::from(anyhow::Error::from(e)))?;
    Ok(())
}
