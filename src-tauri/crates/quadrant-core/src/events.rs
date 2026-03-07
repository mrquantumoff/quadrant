use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ModProgressPayload {
    pub mod_id: String,
    pub progress: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum BackendEvent {
    ModDownloadProgress(ModProgressPayload),
    ModInstallProgress(ModProgressPayload),
    ModpackDownloadProgress(f64),
    QuadrantExportProgress(f64),
    QuadrantShareSubmission(Value),
    RefreshNotifications(Value),
    RecheckAccountToken,
}
