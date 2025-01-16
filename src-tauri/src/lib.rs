use tauri_plugin_cli::CliExt;
use tokio::sync::Mutex;

use config::init_config;
use serde::{Deserialize, Serialize};
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconEvent},
    Manager,
};
use tauri_plugin_updater::UpdaterExt;

use tauri_plugin_deep_link::DeepLinkExt;
pub mod account;
pub mod config;
pub mod mc_mod;
pub mod modpacks;
pub mod other;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AppState {
    pub updated_modpacks: Vec<String>,
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
#[allow(deprecated)]
pub async fn run() {
    colog::init();
    tauri::Builder::default()
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_single_instance::init(|_app, _argv, _cwd| {}))
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_persisted_scope::init())
        .plugin(tauri_plugin_cli::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_deep_link::init())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_store::Builder::new().build())
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .setup(|app| {
            let mut autoupdate = true;

            #[cfg(desktop)]
            {
                app.deep_link().register("quadrantnext")?;
                app.deep_link().register("curseforge")?;
                app.deep_link().register("modrinth")?;

                use tauri_plugin_autostart::MacosLauncher;
                use tauri_plugin_autostart::ManagerExt;

                app.handle()
                    .plugin(tauri_plugin_autostart::init(
                        MacosLauncher::LaunchAgent,
                        Some(vec!["--autostart"]),
                    ))
                    .unwrap();

                // Get the autostart manager
                let autostart_manager = app.autolaunch();
                // Enable autostart
                let _ = autostart_manager.enable();

                // Check enable state
                println!(
                    "registered for autostart? {}",
                    autostart_manager.is_enabled().unwrap()
                );
            }
            init_config(app.handle().clone())?;
            app.manage(Mutex::new(AppState::default()));
            match app.cli().matches() {
                Ok(matches) => {
                    log::info!("Matches: {:?}", matches);
                    let autostart = matches.args.get_key_value("autostart");
                    if autostart.is_some() {
                        let autostart = autostart.unwrap();
                        if autostart.1.value == true {
                            log::info!("Autostarting");
                            for window in app.webview_windows() {
                                window.1.hide()?;
                            }
                        }
                    }
                    let autoupdater_disabled = matches.args.get_key_value("noupdater");
                    if autoupdater_disabled.is_some() {
                        let autoupdater_disabled = autoupdater_disabled.unwrap();
                        autoupdate = autoupdater_disabled.1.value == true;
                    }
                }
                Err(_) => {
                    log::error!("No matches");
                }
            }
            let handle = app.handle().clone();

            if autoupdate && !cfg!(dev) {
                tauri::async_runtime::spawn(async move {
                    update(handle).await.unwrap();
                });
            }
            let handle = app.handle().clone();

            tauri::async_runtime::spawn(async move {
                other::telemetry::send_telemetry(handle.clone().to_owned()).await;
            });

            let app_handle = app.handle().clone();
            let mut interval_timer =
                tokio::time::interval(chrono::Duration::seconds(3).to_std().unwrap());

            let _ = tokio::task::spawn(async move {
                loop {
                    interval_timer.tick().await;
                    let _task = account::id::check_account_updates(app_handle.clone()).await;
                }
            });

            let tray = app.tray_by_id("main");
            if tray.is_some() {
                let tray = tray.unwrap();
                tray.set_title(Some("Quadrant"))?;
                let quit_i = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
                let menu = Menu::with_items(app, &[&quit_i])?;

                tray.set_menu(Some(menu))?;
                tray.set_show_menu_on_left_click(false)?;
                tray.on_tray_icon_event(|tray, event| match event {
                    TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } => {
                        if let Some(window) = tray.app_handle().get_webview_window("main") {
                            window.set_enabled(true).unwrap();

                            window.show().unwrap();
                            window.set_focus().unwrap();
                            window.unminimize().unwrap();
                        }
                    }
                    _ => {}
                });
                tray.on_menu_event(|app, event| match event.id.as_ref() {
                    "quit" => {
                        app.exit(0);
                    }
                    _ => {}
                });
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            modpacks::general::get_modpacks,
            modpacks::general::frontend_apply_modpack,
            modpacks::manage_modpack::delete_mod,
            modpacks::manage_modpack::update_modpack,
            modpacks::manage_modpack::create_modpack,
            modpacks::manage_modpack::delete_modpack,
            modpacks::manage_modpack::open_modpacks_folder,
            modpacks::general::install_modpack,
            mc_mod::curseforge::get_mod_curseforge,
            mc_mod::modrinth::get_mod_modrinth,
            mc_mod::search_mods,
            mc_mod::get_versions,
            mc_mod::get_user_url,
            mc_mod::install_mod,
            mc_mod::curseforge::get_mod_owners_curseforge,
            mc_mod::modrinth::get_mod_owners_modrinth,
            mc_mod::modrinth::get_mod_deps_modrinth,
            mc_mod::curseforge::get_mod_deps_curseforge,
            mc_mod::check_mod_updates,
            mc_mod::install_remote_file,
            account::quadrant_share::get_quadrant_share_modpack,
            config::init_config,
            config::get_minecraft_folder,
            other::open_link,
            account::set_secret,
            account::clear_account_token,
            account::id::get_account_info,
            account::id::oauth2_login,
            account::id::read_notification,
            account::quadrant_share::share_modpack,
            account::quadrant_share::share_modpack_raw,
            account::quadrant_sync::get_synced_modpacks,
            account::quadrant_sync::kick_member,
            account::quadrant_sync::invite_member,
            account::quadrant_sync::sync_modpack,
            account::quadrant_sync::delete_synced_modpack,
            account::quadrant_sync::answer_invite,
            other::telemetry::send_telemetry,
            other::telemetry::remove_telemetry,
            modpacks::general::set_modpack_sync_date,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

async fn update(app: tauri::AppHandle) -> tauri_plugin_updater::Result<()> {
    if let Some(update) = app.updater()?.check().await? {
        let mut downloaded = 0;

        // alternatively we could also call update.download() and update.install() separately
        update
            .download_and_install(
                |chunk_length, content_length| {
                    downloaded += chunk_length;
                    log::info!("downloaded {downloaded} from {content_length:?}");
                },
                || {
                    log::info!("download finished");
                },
            )
            .await?;

        println!("update installed");
        app.restart();
    }

    Ok(())
}
