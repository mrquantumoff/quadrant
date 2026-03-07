use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::{
    Result,
    account::{QNT_BASE_URL, get_account_token},
    models::{LocalModpack, ModLoader},
    ports::SecretStore,
};

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ModpackOwner {
    pub username: String,
    pub admin: bool,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct SyncedModpack {
    pub name: String,
    pub minecraft_version: String,
    pub mod_loader: ModLoader,
    pub mods: String,
    pub owners: Vec<ModpackOwner>,
    pub last_synced: i64,
    pub modpack_id: String,
}

pub async fn get_synced_modpacks(
    secret_store: &impl SecretStore,
    user_agent: &str,
    show_owners: bool,
    modpack_id: Option<String>,
) -> Result<Vec<SyncedModpack>> {
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

pub async fn kick_member(
    secret_store: &impl SecretStore,
    user_agent: &str,
    modpack_id: String,
    username: String,
) -> Result<()> {
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

pub async fn invite_member(
    secret_store: &impl SecretStore,
    user_agent: &str,
    modpack_id: String,
    username: String,
    admin: bool,
) -> Result<()> {
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

pub async fn delete_synced_modpack(
    secret_store: &impl SecretStore,
    user_agent: &str,
    modpack_id: String,
) -> Result<()> {
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

pub async fn sync_modpack(
    secret_store: &impl SecretStore,
    user_agent: &str,
    modpack: LocalModpack,
    overwrite: bool,
) -> Result<i64> {
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

pub async fn answer_invite(
    secret_store: &impl SecretStore,
    user_agent: &str,
    modpack_id: String,
    answer: bool,
) -> Result<()> {
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
