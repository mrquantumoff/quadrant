use mc_mod::get_user_agent;
use other::open_link;
use tauri_plugin_cli::CliExt;
use tauri_plugin_store::StoreExt;
use tokio::sync::Mutex;

use config::init_config;
use serde::{Deserialize, Serialize};
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconEvent},
    Emitter, Manager, Url,
};
use tauri_plugin_updater::UpdaterExt;

use tauri_plugin_deep_link::DeepLinkExt;

#[allow(dead_code)] // This is used in the  Quadrant ID feature
pub(crate) const QNT_BASE_URL: &'static str = "https://api.mrquantumoff.dev/api/v3";

#[cfg(feature = "quadrant_id")]
pub mod account;

pub mod config;
pub mod mc_mod;
pub mod modpacks;
pub mod other;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AppState {
    pub updated_modpacks: Vec<String>,
    pub is_update_enabled: bool,
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
#[allow(deprecated)]
pub async fn run() {
    colog::init();
    log::info!("Initializing Tauri...");
    let mut builder =
        tauri::Builder::default().plugin(tauri_plugin_updater::Builder::new().build());
    #[cfg(desktop)]
    {
        builder = builder.plugin(tauri_plugin_single_instance::init(|app, argv, _| {
            log::info!("a new app instance was opened with {argv:?} and the deep link event was already triggered");
            let w = app.get_webview_window("main").expect("no main window");
            match w.show() {
                Ok(_) => {}
                Err(e) => {
                    log::error!("Failed to show window: {}", e);
                }
            }
            match w.set_focus() {
                Ok(_) => {}
                Err(e) => {
                    log::error!("Failed to focus window: {}", e);
                }
            }
            match w.unminimize() {
                Ok(_) => {}
                Err(e) => {
                    log::error!("Failed to unminimize window: {}", e);
                }
            }
            match w.center() {
                Ok(_) => {}
                Err(e) => {
                    log::error!("Failed to center window: {}", e);
                }
            }
        }));
    }
    builder = builder
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
            init_config(app.handle().clone())?;
            log::info!("Initializing app...\nInitializing config...");
            let mut autoupdate = true;

            log::info!("Initializing deep links and autostart...");
            #[cfg(desktop)]
            {
                match app.deep_link().register_all() {
                    Ok(_) => {}
                    Err(e) => {
                        log::error!("Failed to register deep links: {}", e);
                    }
                }

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

            if cfg!(dev) == false {
                app.emit("disableRightClick", true).unwrap();
                log::info!("Disabling right click...");
            }

            match app.cli().matches() {
                Ok(matches) => {
                    log::info!("Matches: {:?}", matches);
                    let autostart = matches.args.get_key_value("autostart");
                    if autostart.is_some() {
                        let autostart = autostart.unwrap();
                        if autostart.1.value == true {
                            log::info!("Autostarting");
                            for window in app.webview_windows() {
                                match window.1.hide() {
                                    Ok(_) => {}
                                    Err(e) => {
                                        log::error!("Failed to hide window: {}", e);
                                    }
                                }
                            }
                        }
                    }
                    let autoupdater_disabled = matches.args.get_key_value("noupdater");
                    if autoupdater_disabled.is_some() {
                        let autoupdater_disabled = autoupdater_disabled.unwrap();

                        let value = autoupdater_disabled.1.value == true;

                        autoupdate = !value;
                    }
                }
                Err(_) => {
                    log::error!("No matches");
                }
            }
            let handle = app.handle().clone();
            log::info!("Autoupdate enabled: {}\nInitializing state...", autoupdate);
            app.manage(Mutex::new(AppState {
                is_update_enabled: autoupdate,
                ..Default::default()
            }));
            if autoupdate {
                log::info!("Checking for updates...");
                tauri::async_runtime::spawn(async move {
                    let res = update(handle).await;
                    if res.is_err() {
                        log::error!("Failed to update, {}", res.err().unwrap());
                        return;
                    }
                    res.unwrap();
                });
            }
            #[cfg(feature = "telemetry")]
            {
                let handle = app.handle().clone();
                log::info!("Initializing telemetry...");
                tauri::async_runtime::spawn(async move {
                    other::telemetry::send_telemetry(handle.clone().to_owned()).await;
                });
            }
            #[cfg(feature = "quadrant_id")]
            {
                log::info!("Starting the check for account updates...");
                let app_handle = app.handle().clone();
                let mut interval_timer =
                    tokio::time::interval(chrono::Duration::seconds(3).to_std().unwrap());

                let _ = tokio::task::spawn(async move {
                    loop {
                        interval_timer.tick().await;
                        let _task = account::id::check_account_updates(app_handle.clone()).await;
                    }
                });
            }
            log::info!("Initializing tray...");
            let tray = app.tray_by_id("main");
            if tray.is_some() {
                let tray = tray.unwrap();
                tray.set_title(Some("Quadrant"))?;
                let quit_i = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
                let show_w = MenuItem::with_id(app, "show", "Show/Hide", true, None::<&str>)?;
                let menu = Menu::with_items(app, &[&show_w, &quit_i])?;

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
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            if window.is_visible().unwrap() {
                                window.hide().unwrap();
                            } else {
                                window.show().unwrap();
                                window.set_focus().unwrap();
                                window.unminimize().unwrap();
                            }
                        }
                    }
                    _ => {}
                });
            }

            log::info!("Updating Minecraft versions...");
            let app_handle = app.handle().clone();
            let _task = tokio::task::spawn(async move {
                let _res = mc_mod::fetch_versions(app_handle).await;
                match _res {
                    Ok(_) => {}
                    Err(e) => {
                        log::error!("Failed to update Minecraft versions: {}", e);
                    }
                }
            });

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
            mc_mod::modrinth::get_mod_modrinth,
            mc_mod::search_mods,
            mc_mod::get_versions,
            mc_mod::get_user_url,
            mc_mod::install_mod,
            mc_mod::modrinth::get_mod_owners_modrinth,
            mc_mod::modrinth::get_mod_deps_modrinth,
            mc_mod::check_mod_updates,
            mc_mod::install_remote_file,
            config::init_config,
            config::get_minecraft_folder,
            other::open_link,
            modpacks::general::set_modpack_sync_date,
            request_check_for_updates,
            is_autoupdate_enabled
        ]);
    #[cfg(feature = "curseforge")]
    {
        builder = builder.invoke_handler(tauri::generate_handler![
            mc_mod::curseforge::get_mod_curseforge,
            mc_mod::curseforge::get_mod_owners_curseforge,
            mc_mod::curseforge::get_mod_deps_curseforge,
        ]);
    }
    #[cfg(feature = "telemetry")]
    {
        builder = builder.invoke_handler(tauri::generate_handler![
            other::telemetry::send_telemetry,
            other::telemetry::remove_telemetry,
        ]);
    }
    #[cfg(feature = "quadrant_id")]
    {
        builder = builder.invoke_handler(tauri::generate_handler![
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
            account::quadrant_share::get_quadrant_share_modpack,
        ]);
    }
    builder
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[tauri::command]
async fn request_check_for_updates(app: tauri::AppHandle) -> Result<(), tauri::Error> {
    update(app).await.map_err(|e| tauri::Error::from(e))
}

#[tauri::command]
async fn is_autoupdate_enabled(app: tauri::AppHandle) -> Result<bool, tauri::Error> {
    let state = app.state::<Mutex<AppState>>();
    let state = state.lock().await;
    Ok(state.is_update_enabled)
}
async fn update(app: tauri::AppHandle) -> Result<(), anyhow::Error> {
    let update_url = Url::parse(&format!("https://api.mrquantumoff.dev/api/any/quadrant/updates/stable/{{{{target}}}}//{{{{arch}}}}//{{{{current_version}}}}"))?;

    let mut update_urls = vec![update_url];

    let update_config = app.store("updateConfig.json")?;

    if update_config.get("channel").is_some() {
        let channel = update_config.get("channel").unwrap();
        let channel = channel.as_str().unwrap_or_else(|| "stable");
        if channel != "stable" {
            update_urls.push(Url::parse(&format!("https://api.mrquantumoff.dev/api/any/quadrant/updates/{}/{{{{target}}}}//{{{{arch}}}}//{{{{current_version}}}}",channel))?);
        }
    }
    // Prefer the preview version if we're updating from a preview version
    update_urls.reverse();

    log::info!("Update URLs: {:?}", update_urls);

    let updater = app
        .updater_builder()
        .endpoints(update_urls)?
        // .version_comparator(|current, update| current != update.version)
        .header("User-Agent", get_user_agent())?
        .build()?;

    if let Some(update) = updater.check().await? {
        let mut downloaded = 0;

        // alternatively we could also call update.download() and update.install() separately
        update
            .download_and_install(
                |chunk_length, content_length| {
                    downloaded += chunk_length;
                    let progress = downloaded as f64 / content_length.unwrap() as f64;
                    log::info!("downloaded {}", progress);
                    app.emit("updateDownloadProgress", progress).unwrap();
                },
                || {
                    log::info!("download finished");
                },
            )
            .await?;

        println!("update installed");
        let config = app.store("config.json")?;
        if config.get("rssFeeds").is_some() {
            let rss_feeds = config.get("rssFeeds").unwrap();
            let rss_feeds = rss_feeds.as_bool().unwrap_or(true);
            if rss_feeds {
                open_link("https://blog.mrquantumoff.dev".to_string())?;
            }
        }
        app.emit("updateDownloadProgress", 1).unwrap();
        app.restart();
    }

    Ok(())
}
