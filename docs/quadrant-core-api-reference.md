# Quadrant Core API Reference

This is a practical reference for the main public modules and the entrypoints a host or frontend-facing adapter will normally use.

Use this together with:

- [quadrant-core.md](./quadrant-core.md)
- [quadrant-core-architecture.md](./quadrant-core-architecture.md)
- [creating-a-quadrant-frontend.md](./creating-a-quadrant-frontend.md)

## Crate Root

Public modules:

- `account`
- `config`
- `events`
- `mc_mod`
- `models`
- `modpacks`
- `ports`
- `rss`
- `telemetry`

Shared result alias:

- `quadrant_core::Result`

## `ports`

### `SettingsStore`

Required:

- `get_value(&self, key: &str) -> Result<Option<Value>>`
- `set_value(&self, key: &str, value: Value) -> Result<()>`
- `entries(&self) -> Result<Vec<(String, Value)>>`

Helpers:

- `get_bool`
- `get_i64`
- `get_string`
- `set_bool`
- `set_i64`
- `set_string`

Expected usage:

- `config`
- `mc_mod`
- `account`
- `telemetry`

### `SecretStore`

Required:

- `get_secret`
- `set_secret`
- `delete_secret`

Expected usage:

- account token and refresh token management

### `EventSink`

Required:

- `publish(&self, event: BackendEvent) -> Result<()>`

Expected usage:

- progress events during downloads and exports
- frontend refresh events

### `Shell`

Current purpose:

- open URLs
- open filesystem paths
- choose export paths

This trait exists for hosts, but current extracted logic uses it less than `SettingsStore` and `EventSink`.

### `Notifier`

Current purpose:

- host-side notifications for update and sync flows

### `RuntimeState`

Current purpose:

- bridge in-process host state such as updater flags or dedupe state

## `events`

### `BackendEvent`

- `ModDownloadProgress(ModProgressPayload)`
- `ModInstallProgress(ModProgressPayload)`
- `ModpackDownloadProgress(f64)`
- `QuadrantExportProgress(f64)`
- `QuadrantShareSubmission(Value)`
- `RefreshNotifications(Value)`
- `RecheckAccountToken`

### `ModProgressPayload`

- `mod_id: String`
- `progress: i32`

## `config`

### Directory helpers

- `get_config_dir()`
- `get_mc_folder()`

### Defaults

- `default_app_config()`
- `default_update_config()`

### Initialization

- `ensure_default_app_config(store: &impl SettingsStore)`

Important config keys materialized by default:

- `clipIcons`
- `lastRSSfetched`
- `curseforge`
- `modrinth`
- `curseforgeUsage`
- `modrinthUsage`
- `devMode`
- `hardwareId`
- `rssFeeds`
- `silentNews`
- `autoQuadrantSync`
- `showUnupgradeableMods`
- `lastPage`
- `extendedNavigation`
- `experimentalFeatures`
- `dontShowUserDataRecommendation`
- `cacheKeepAlive`
- `syncSettings`
- `lastSettingsUpdated`
- `mcFolder`
- `collectUserData`

Host note:

- if you want to stay compatible with existing Quadrant data, keep these keys unchanged
- `ensure_default_app_config` is the expected bootstrap step before calling other services

## `models`

Core shared types:

- `ModSource`
- `InstalledMod`
- `ModLoader`
- `InstalledModpack`
- `LocalModpack`
- `SyncInfo`
- `Article`

Utility:

- `modpack_path(mc_folder, modpack_name)`

## `modpacks`

### Discovery and selection

- `get_modpacks(mc_folder, hide_free)`
- `apply_modpack(mc_folder, name)`

### CRUD

- `create_modpack(mc_folder, existing_modpacks, name, version, mod_loader)`
- `update_modpack(mc_folder, existing_modpacks, modpack_source, name, version, mod_loader)`
- `delete_modpack(mc_folder, existing_modpacks, name)`

### Mod membership

- `register_mod(mc_folder, existing_modpacks, mod_, modpack_name)`
- `delete_mod(mc_folder, existing_modpacks, modpack_name, mod_id)`

### Sync metadata

- `set_modpack_sync_date(mc_folder, time, modpack)`

### Download and export

- `install_modpack(mc_folder, mod_config, settings, event_sink)`
- `export_modpack_to(mc_folder, modpack, destination, event_sink)`

Operational note:

- `apply_modpack` and the export/install flows operate on the existing Quadrant on-disk layout, so hosts should treat that layout as part of the compatibility contract

## `mc_mod`

### Shared types

- `ModType`
- `Mod`
- `MinecraftVersion`
- `UniversalModFile`
- `GlobalSearchModsArgs`
- `SearchModsArgs`
- `GetModArgs`
- `IdentifiedMod`

### General operations

- `get_versions()`
- `search_mods(args, settings)`
- `check_mod_updates(mod_to_update, minecraft_version, mod_loader, modpack, show_unupgradeable_mods)`
- `install_mod(mc_folder, existing_modpacks, settings, event_sink, ...)`
- `install_remote_file(mc_folder, existing_modpacks, event_sink, ...)`
- `identify_modpack(mc_folder, modpack, curseforge_enabled, modrinth_enabled)`
- `get_mod_url(slug, mod_type, source)`
- `get_user_url(username, source)`
- `get_user_agent()`

Feature note:

- CurseForge-specific APIs require the `curseforge` feature

### Provider submodules

#### `mc_mod::modrinth`

- `search_mods_modrinth`
- `get_mod_modrinth`
- `get_mod_owners_modrinth`
- `get_mod_deps_modrinth`
- `get_latest_mod_version_modrinth`
- `download_mod_modrinth`
- `identify_modpack_modrinth`

#### `mc_mod::curseforge`

Only available with the `curseforge` feature.

- `get_mod_curseforge`
- `get_mod_owners_curseforge`
- `get_mod_deps_curseforge`
- `search_mods_curseforge`
- `get_latest_mod_version_curseforge`
- `download_mod_curseforge`
- `identify_modpack_curseforge`

#### `mc_mod::cache`

- `init_cache`
- `file_hash`
- `get_cache_index`
- `add_cache_index`

## `account`

### Shared helpers

- `set_secret(secret_store, key, value)`
- `get_account_token(secret_store)`
- `get_refresh_token(secret_store)`
- `clear_account_token(secret_store)`

### `account::id`

- `try_refresh_token`
- `get_account_info`
- `get_account_info_with_refresh`
- `oauth2_login`
- `read_notification`
- `determine_pending_modpack_updates`

Important types:

- `AccountInfo`
- `Notification`
- `OAuth2Response`
- `PendingModpackUpdate`

### `account::quadrant_sync`

- `get_synced_modpacks`
- `kick_member`
- `invite_member`
- `delete_synced_modpack`
- `sync_modpack`
- `answer_invite`

Important types:

- `ModpackOwner`
- `SyncedModpack`

### `account::quadrant_share`

- `share_modpack_raw`
- `get_quadrant_share_modpack`

Important types:

- `QuadrantShareSubmissionResponse`
- `QuadrantShareSubmission`
- `QuadrantShareResponse`

### `account::quadrant_settings_sync`

- `get_quadrant_settings`
- `submit_quadrant_settings`
- `SYNCED_KEYS`

Host note:

- keep account tokens in `SecretStore`, not in `SettingsStore`
- refresh and notification scheduling remain host responsibilities even though the HTTP logic is in core

## `rss`

- `get_news() -> Result<Vec<Article>>`

## `telemetry`

- `get_telemetry_info(settings_store, version, os)`
- `send_telemetry(settings_store, user_agent, version, os, api_key)`
- `remove_telemetry(settings_store, user_agent, api_key)`

Important type:

- `AppInfo`

## Typical Call Graphs

### App startup

1. `config::ensure_default_app_config`
2. `config::get_mc_folder`
3. optional account refresh using `account::id`
4. `modpacks::get_modpacks`

### Install a mod

1. `mc_mod::search_mods`
2. `mc_mod` provider-specific detail fetch
3. `mc_mod::install_mod`
4. forward `BackendEvent::ModDownloadProgress` and `BackendEvent::ModInstallProgress`

### Export a modpack

1. host chooses destination path
2. `modpacks::export_modpack_to`
3. forward `BackendEvent::QuadrantExportProgress`

### Sync or share

1. read account token from `SecretStore`
2. call `account::quadrant_sync` or `account::quadrant_share`
3. forward refresh-related events as needed
