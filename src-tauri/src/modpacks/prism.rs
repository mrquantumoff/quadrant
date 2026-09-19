use quadrant_core::prism::PrismInstance;
use quadrant_host::QuadrantHost;
use tauri::{AppHandle, Manager};

#[tauri::command]
pub fn get_prism_instances(app: AppHandle) -> Vec<PrismInstance> {
    app.state::<QuadrantHost>()
        .get_prism_instances()
        .unwrap_or_else(|error| {
            // The renderer treats this as "no instances"; leave a trace so an
            // empty list caused by an unreadable Prism folder is diagnosable.
            log::error!("Failed to list Prism instances: {error}");
            Vec::new()
        })
}

#[tauri::command]
pub async fn apply_modpack_to_prism_instance(
    name: String,
    instance_id: String,
    app: AppHandle,
) -> Result<(), tauri::Error> {
    app.state::<QuadrantHost>()
        .apply_modpack_to_prism_instance(name, instance_id)
        .await
        .map_err(crate::command_error)
}

#[tauri::command]
pub fn detach_prism_instance(instance_id: String, app: AppHandle) -> Result<(), tauri::Error> {
    app.state::<QuadrantHost>()
        .detach_prism_instance(instance_id)
        .map_err(crate::command_error)
}
