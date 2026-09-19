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
- `content`
- `events`
- `mc_mod`
- `models`
- `modpacks`
- `ports`
- `prism`
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

Keys a host may store but that are not materialized by default:

- `prismLauncherFolder`: optional path override for the Prism Launcher data directory. Machine-specific, so it is deliberately excluded from the defaults and from cloud settings sync.

Host note:

- if you want to stay compatible with existing Quadrant data, keep these keys unchanged
- `ensure_default_app_config` is the expected bootstrap step before calling other services
- `quadrant-host` exposes `get_config_value`, `set_config_value` and `remove_config_value` (`key`). Clearing a key goes through `remove_config_value`, which drops it from the store so a later read falls back to the default; storing a JSON `null` instead leaves a value behind, and readers such as `prismLauncherFolder` only tolerate that for configs older versions wrote

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

## `prism`

Experimental, gated by the `experimentalFeatures` config key. Applies a Quadrant modpack to a Prism Launcher instance and keeps that instance's Minecraft version and mod loader in sync with it.

### Shared types

- `PrismInstance`

### Discovery

- `default_data_dirs()`
- `find_data_dir(override_dir)`
- `instances_dir(data_dir)`
- `game_dir(instance_dir)`
- `list_instances(instances_dir, mc_folder)`
- `resolve_instance_dir(instances_dir, instance_id)`
- `read_pack_manifest(instances_dir, instance_id)`
- `content_roots(mc_folder, instances_dir, modpack)`

### Selection

- `apply_modpack_to_instance(mc_folder, instances_dir, instance_id, modpack, loader_version)`
- `detach_instance(instances_dir, instance_id)`

### Component sync

- `sync_components(pack, minecraft_version, loader, loader_version)`
- `needs_loader_version(pack, minecraft_version, loader)`
- `loader_component_uid(loader)`
- `resolve_loader_version(loader, minecraft_version)`

Operational notes:

- which modpack an instance uses is derived from its `<game dir>/mods` symlink target, exactly as `get_modpacks` derives `is_applied`; no binding is persisted
- `sync_components` edits `mmc-pack.json` as raw JSON so fields Quadrant does not model survive, and returns `false` when nothing changed so the file is not rewritten
- a manifest that does not declare `formatVersion: 1` is refused rather than rewritten
- `resolve_loader_version` reads the Prism meta server at `https://meta.prismlauncher.org`, so call it only when `needs_loader_version` is true

## `content`

Read-only listing of the resource packs and shader packs installed in a game directory, which is either the Minecraft folder or a Prism Launcher instance's.

### Shared types

- `ContentFile`
- `ContentLocation`
- `ContentLocationKind`
- `LocationRef`

### Listing

- `list_content_files(dir)`
- `content_location(id, kind, name, game_dir, include_files)`
- `content_subfolder(mod_type)`

### Location ids

- `MINECRAFT_LOCATION_ID`
- `prism_location_id(instance_id)`
- `parse_location_id(id)`

### Copying and deleting

- `copy_content_files(from_dir, to_dir, file_names)`
- `delete_content_files(dir, file_names)`

Operational notes:

- a location is addressed by its id, so a frontend never hands the backend a filesystem path to read or open
- a missing or unreadable folder lists as empty rather than failing, because a game directory only grows these folders once something is installed into it
- only directories and `.zip` files are listed, which drops the sidecar option files a shader loader writes next to a pack
- `content_subfolder` is `None` for every type but `ResourcePack` and `ShaderPack`, and is the single source of the `resourcepacks`/`shaderpacks` folder names, including for `mc_mod::install_local_file`
- `content_location` with `include_files` false does not read the pack folders at all and returns both lists empty, for a caller that only needs each location's id, name and path
- both `copy_content_files` and `delete_content_files` take bare file names from a listing: each must be a single path component (`InvalidRequest` otherwise) and must name a pack the listing would show (`ContentMissing` otherwise), and every name is checked before anything is written or removed
- copying into the source folder is `InvalidRequest`, and a destination entry that already exists is overwritten, so a repeated copy converges instead of failing
- a `.zip` is streamed through a sibling temp file and renamed into place, and a symlink inside a pack folder is skipped rather than followed out of the pack
- the two differ on a name that is not there: copying it is `ContentMissing`, while deleting it is skipped and left out of the count, so a retry after a partial failure converges
- deletion is permanent, matching `modpacks::delete_modpack`, and a linked pack is unlinked rather than followed, so what it points at survives

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

Type note:

- `ModType` serializes as its variant name and also accepts `Shader` for `ShaderPack`, the label older frontends and N-API consumers send

### General operations

- `get_versions()`
- `search_mods(args, settings)`
- `check_mod_updates(mod_to_update, minecraft_version, mod_loader, modpack, show_unupgradeable_mods)`
- `install_mod(install_roots, settings, event_sink, ...)`
- `install_remote_file(install_roots, event_sink, ...)`
- `identify_modpack(mc_folder, modpack, curseforge_enabled, modrinth_enabled)`
- `get_mod_url(slug, mod_type, source)`
- `get_user_url(username, source)`
- `get_user_agent()`

Install note:

- `install_mod` and `install_remote_file` take a slice of install roots. They resolve, download and enrich once and then place the file into every root, so progress events fire once per install rather than once per root. An empty slice is `InvalidRequest`. Only a `Mod` returns an updated `LocalModpack`, and it always has exactly one root.

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

### Apply a modpack to a Prism Launcher instance

Exposed by `quadrant-host` as the `get_prism_instances`, `apply_modpack_to_prism_instance` (`name`, `instanceId`) and `detach_prism_instance` (`instanceId`) commands.

1. check the `experimentalFeatures` config key
2. `prism::find_data_dir` with the `prismLauncherFolder` override, then `prism::instances_dir`
3. `prism::list_instances`, or `modpacks::get_modpacks` to find the modpack to apply
4. `prism::needs_loader_version` against `prism::read_pack_manifest`, and only then `prism::resolve_loader_version`
5. `prism::apply_modpack_to_instance`, or `prism::detach_instance` to unlink

Resource pack and shader installs hand `prism::content_roots` straight to `mc_mod::install_mod` as its install roots, so one call places the file in every root the modpack is applied to, unless the caller names one content location.

### List, install into, copy between, and clear out content locations

Exposed by `quadrant-host` as the `get_installed_content` (`includeFiles`, default true), `copy_content` (`fromLocation`, `toLocation`, `modType`, `fileNames`) and `delete_content` (`location`, `modType`, `fileNames`) commands. Passing `includeFiles: false` returns the locations with empty `resourcePacks`/`shaderPacks` and reads no pack folder, which is what a caller that only needs ids and names should send. Opening a listed folder is a shell concern, so `content_folder(locationId, modType)` is host API only and the Tauri shell wraps it in `open_content_folder`.

1. `content::content_location` for the Minecraft folder
2. `prism::list_instances`, then `prism::game_dir` and `content::prism_location_id` per instance
3. `content::parse_location_id` and `content::content_subfolder` to turn a listed id back into a folder, which for a Prism id goes through `prism::resolve_instance_dir`
4. `content::copy_content_files` between two such folders, or `content::delete_content_files` within one, which `copy_content` and `delete_content` return the number of copied or removed packs from

`install_mod` takes an optional `contentLocation` id. For a `ResourcePack` or `ShaderPack` it makes that location's game directory the single install root, and for every other type it is ignored. Omitting it keeps the modpack-following behaviour above. `install_remote_file` has no such argument and always follows the modpack. A Prism location id resolves only while `experimentalFeatures` is on, in both the install and the copy path (`Forbidden` otherwise).
