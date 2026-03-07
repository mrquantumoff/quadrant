//! Synced modpack and collaboration APIs.

use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::{
    Result,
    account::{QNT_BASE_URL, get_account_token},
    models::{LocalModpack, ModLoader},
    ports::SecretStore,
};

/// Owner information for a synced modpack.
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ModpackOwner {
    /// Owner username.
    pub username: String,
    /// Whether the owner has admin rights on the synced modpack.
    pub admin: bool,
}

/// Cloud-backed modpack metadata returned by Quadrant Sync.
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct SyncedModpack {
    /// Human-readable modpack name.
    pub name: String,
    /// Target Minecraft version.
    pub minecraft_version: String,
    /// Target mod loader.
    pub mod_loader: ModLoader,
    /// Serialized mod list payload.
    pub mods: String,
    /// Owners and collaborators of the modpack.
    pub owners: Vec<ModpackOwner>,
    /// Last sync time in seconds since the Unix epoch.
    pub last_synced: i64,
    /// Stable cloud modpack identifier.
    pub modpack_id: String,
}

/// Fetches synced modpacks visible to the current account.
pub async fn get_synced_modpacks(
    secret_store: &impl SecretStore,
    user_agent: &str,
    show_owners: bool,
    modpack_id: Option<String>,
) -> Result<Vec<SyncedModpack>> {
    log::info!("Fetching synced modpacks (show_owners={show_owners}, modpack_id={modpack_id:?})");
    let mut query = vec![("show_owners", show_owners.to_string())];
    if let Some(modpack_id) = modpack_id {
        query.push(("modpack_id", modpack_id));
    }
    let response = reqwest::Client::new()
        .get(format!("{}/quadrant/sync/get", QNT_BASE_URL))
        .query(query.as_slice())
        .bearer_auth(get_account_token(secret_store)?)
        .header("User-Agent", user_agent)
        .send()
        .await?;
    Ok(response.json().await?)
}

/// Removes a collaborator from a synced modpack.
pub async fn kick_member(
    secret_store: &impl SecretStore,
    user_agent: &str,
    modpack_id: String,
    username: String,
) -> Result<()> {
    log::info!("Kicking member {username} from modpack {modpack_id}");
    let res = reqwest::Client::new()
        .delete(format!("{}/quadrant/sync/kick", QNT_BASE_URL))
        .bearer_auth(get_account_token(secret_store)?)
        .json(&json!({ "modpack_id": modpack_id, "username": username }))
        .header("User-Agent", user_agent)
        .send()
        .await?;
    if res.status() != 200 {
        return Err(anyhow::anyhow!(res.text().await?));
    }
    Ok(())
}

/// Invites a collaborator to a synced modpack.
pub async fn invite_member(
    secret_store: &impl SecretStore,
    user_agent: &str,
    modpack_id: String,
    username: String,
    admin: bool,
) -> Result<()> {
    log::info!("Inviting member {username} to modpack {modpack_id} (admin={admin})");
    let res = reqwest::Client::new()
        .post(format!("{}/quadrant/sync/invite", QNT_BASE_URL))
        .bearer_auth(get_account_token(secret_store)?)
        .json(&json!({ "modpack_id": modpack_id, "username": username, "admin": admin }))
        .header("User-Agent", user_agent)
        .send()
        .await?;
    if res.status() != 200 {
        return Err(anyhow::anyhow!(res.text().await?));
    }
    Ok(())
}

/// Permanently deletes a synced modpack from the cloud.
pub async fn delete_synced_modpack(
    secret_store: &impl SecretStore,
    user_agent: &str,
    modpack_id: String,
) -> Result<()> {
    log::info!("Deleting synced modpack {modpack_id}");
    let res = reqwest::Client::new()
        .delete(format!("{}/quadrant/sync/delete", QNT_BASE_URL))
        .bearer_auth(get_account_token(secret_store)?)
        .json(&json!({ "modpack_id": modpack_id }))
        .header("User-Agent", user_agent)
        .send()
        .await?;
    if res.status() != 200 {
        return Err(anyhow::anyhow!(res.text().await?));
    }
    Ok(())
}

/// Uploads local modpack state to Quadrant Sync and returns the sync timestamp used.
pub async fn sync_modpack(
    secret_store: &impl SecretStore,
    user_agent: &str,
    modpack: LocalModpack,
    overwrite: bool,
) -> Result<i64> {
    log::info!("Syncing modpack \"{}\" (overwrite={overwrite})", modpack.name);
    let timestamp = Utc::now().timestamp();
    let res = reqwest::Client::new()
        .post(format!("{}/quadrant/sync/submit", QNT_BASE_URL))
        .bearer_auth(get_account_token(secret_store)?)
        .json(&json!({
            "name": modpack.name,
            "mc_version": modpack.version,
            "mod_loader": modpack.mod_loader.to_string(),
            "overwrite": overwrite,
            "mods": serde_json::to_string_pretty(&modpack.mods)?,
            "last_synced": &timestamp,
        }))
        .header("User-Agent", user_agent)
        .send()
        .await?;
    if res.status() != 200 {
        return Err(anyhow::anyhow!(res.text().await?));
    }
    Ok(timestamp)
}

/// Accepts or declines an invitation to a synced modpack.
pub async fn answer_invite(
    secret_store: &impl SecretStore,
    user_agent: &str,
    modpack_id: String,
    answer: bool,
) -> Result<()> {
    log::info!("Answering invite for modpack {modpack_id}: accepted={answer}");
    let response = reqwest::Client::new()
        .post(format!("{}/quadrant/sync/respond", QNT_BASE_URL))
        .bearer_auth(get_account_token(secret_store)?)
        .json(&json!({ "modpack_id": modpack_id, "accept": answer }))
        .header("User-Agent", user_agent)
        .send()
        .await?;
    if !response.status().is_success() {
        return Err(anyhow::anyhow!(response.text().await?));
    }
    Ok(())
}
