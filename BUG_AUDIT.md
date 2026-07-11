# Quadrant — Bug & Unwanted-Behaviour Audit

Read-only audit of the whole codebase (Rust backend under `src-tauri/`, React/TS frontend under `src/`, plus packaging/CI). Every finding below was confirmed by two independent adversarial verifiers (a correctness lens and a reachability lens) that read the actual code; findings that failed either lens are excluded.

Legend: 🔴 critical · 🟠 high · 🟡 medium · ⚪ low

---

## 🔴 Critical

### 1. Path traversal → arbitrary file write (RCE vector) when installing shared/synced modpacks
`src-tauri/crates/quadrant-core/src/modpacks.rs:471` (also name-based at `:421`)

`install_modpack` builds each mod's on-disk path two ways, both from attacker-controlled data with **no sanitization**:

- **Filename**: `modpack_folder.join(urlencoding::decode(download_url.split('/').last()))`. `urlencoding::decode` turns `%2e%2e%2f` / `%2F` into `../`, and `PathBuf::join` preserves `..` (an absolute decoded segment replaces the base entirely). A `download_url` ending in `..%2F..%2F..%2F.config%2Fautostart%2Fevil.desktop` escapes the modpack folder.
- **Folder**: `modpack_path(mc_folder, &mod_config.name)` joins the modpack `name` unsanitized (`models.rs:353`), so a name of `../../../…` redirects the whole install.

The downloaded **content** is whatever the attacker's server returns (`download_mod_concurrently` → `std::fs::File::create` + `write_all`). Both `name` and `download_url` are free-form strings that arrive from untrusted sources:
- **Quadrant Share** — `get_quadrant_share_modpack` (`account/quadrant_share.rs`) deserializes an arbitrary `InstalledModpack` from a 7-digit code / `quadrantnext://` deep link.
- **Quadrant Sync** — `maybe_apply_remote_modpack_update` (`quadrant-host/src/lib.rs:1628`) auto-installs from a server/collaborator-provided JSON when `autoQuadrantSync` is on, which **defaults to true** (`config.rs:105`) and needs no user click.

**Impact:** attacker-chosen bytes written to an attacker-chosen path (e.g. `~/.config/autostart/*.desktop` → code execution on next login). `delete_mod` (`:369`) uses the identical decode → `std::fs::remove_file`, giving arbitrary file **deletion** as well.

**Fix direction:** reject any decoded filename/name containing path separators or `..`, canonicalize the final path and assert it stays within the modpack folder, and validate `download_url` scheme/host against an allowlist before fetching.

---

## 🟠 High

### 2. Frontend and backend both own `config.json`, silently reverting each other's writes
`src-tauri/crates/quadrant-host/src/lib.rs:390`, `src-tauri/src/lib.rs:44`, `src/App.tsx:134`

The host writes `app_data_dir/config.json` directly via its `JsonFileStore` (notification cursor, usage counters, remote settings from the 120 s sync worker, `mcFolder`). The frontend independently opens the **same file** via `tauri-plugin-store` `LazyStore("config.json")`, which loads the file once into a cached snapshot and rewrites the whole file on every `save()` **without re-reading disk**. So any settings toggle serializes a stale snapshot that deletes host-written keys. Consequences: cloud-applied settings revert, the notification cursor is wiped (notifications get re-fetched and re-processed from the start → re-triggering auto modpack installs), and `App.tsx` then bumps `lastSettingsUpdated`, uploading the reverted state to the cloud. This is the root cause of several "my settings won't stick" classes of bug.

### 3. Fresh install pushes default settings to the cloud, wiping synced settings on other devices
`src-tauri/crates/quadrant-host/src/lib.rs:1683`, `quadrant-core/src/config.rs:114`

On first run, `ensure_default_app_config` sets `lastSettingsUpdated = Utc::now()` and `syncSettings` defaults true. The 120 s `settings_sync_loop` compares this fresh timestamp to the cloud `sync_date`, concludes "local is newer", and uploads the **default** config — clobbering the user's real cloud settings, which then propagate back to their original device.

### 4. Downloaded jars are never integrity-checked; truncated or error-page downloads are cached and installed as "successful"
`src-tauri/crates/quadrant-core/src/mc_mod/mod.rs:544` and `:557`

Two defects in `get_file`:
- The stream loop is `while let Some(Ok(new_bytes)) = body.next().await` — a mid-stream `Err` (reset/timeout) just **exits the loop as if finished**. The partial bytes are hashed, cached, and installed; progress jumps to 100 %; no error surfaces.
- No `error_for_status()` — a 403/404/5xx CDN response body (HTML/JSON) is written out as the `.jar`. The provider-supplied `file.sha1` (the very key used for the next cache lookup) is **never compared** to the computed hash, so corrupt content is accepted silently and lingers in the cache for 90 days.

### 5. CurseForge `downloadUrl: null` breaks deserialization for any distribution-disabled mod
`src-tauri/crates/quadrant-core/src/mc_mod/curseforge.rs:70`

`ModFile.download_url` is a required `String`. CurseForge returns `"downloadUrl": null` for every file of a mod whose author disabled third-party distribution (many popular mods). `response.json::<…>()` then fails with `invalid type: null` for the whole payload. Because the same struct backs the fingerprint endpoint, a single such jar in a modpack aborts **all** of modpack identification. Should be `Option<String>`.

### 6. CurseForge dependency resolution always returns an empty list
`src-tauri/crates/quadrant-core/src/mc_mod/curseforge.rs:205`

`get_mod_deps_curseforge` reads dependencies from `latestFileIndexes[n].dependencies`, but that path doesn't exist (deps live under `data.latestFiles[n].dependencies`), so `as_array()` always yields empty. And even with the right path, it reads a string `id` while the field is numeric `modId`. Net: required dependencies are never shown, so users install mods that then crash Minecraft with missing-library errors.

### 7. `get_modpacks` calls `read_dir` before the `is_dir` check — one stray file breaks all modpack listing
`src-tauri/crates/quadrant-core/src/modpacks.rs:35`

`std::fs::read_dir(&path)?.count()` runs on every entry before `if !path.is_dir() { continue; }`. `read_dir` on a regular file returns `ENOTDIR`, `?` aborts the function, and the Tauri wrapper swallows it into an empty `Vec` (`general.rs:20`). A `.DS_Store`, `Thumbs.db`, `desktop.ini`, or a leftover exported `.zip` in `<mc>/modpacks` makes the app show **zero** modpacks and breaks nearly every command that routes through `get_modpacks`. (Same pattern in `modrinth.rs:333`, `curseforge.rs:422`.)

### 8. `apply_modpack` backup name uses an RFC2822 timestamp with `:` — modpack switching is broken on Windows
`src-tauri/crates/quadrant-core/src/modpacks.rs:185`

When a real (non-symlink) `mods` directory exists, it's renamed to `mods backup from {Utc::now().to_rfc2822()}` — e.g. `…Fri, 11 Jul 2026 08:15:30 +0000`. Colons are illegal in Windows filenames, so `std::fs::rename` fails, `apply_modpack` errors, and applying any modpack is impossible until the user manually deletes the `mods` folder.

### 9. Concurrent installs into the same modpack race on `modConfigV2.json` and lose entries
`src-tauri/crates/quadrant-core/src/mc_mod/mod.rs:587`, host at `quadrant-host/src/lib.rs:635/660`

The host snapshots the mod list via `get_modpacks()` **before** the multi-second download, then `install_local_file` rewrites the whole manifest from that stale snapshot. Tauri commands run concurrently with no lock. Clicking Download on mod A then mod B (the per-mod buttons allow it) makes B's write erase A's entry; A's jar stays on disk as an untracked "unknown mod" that can't be updated or deleted from the UI.

### 10. Close (X) disables the window; tray "Show" and deep-link/second-launch restore never re-enable it
`src/App.tsx:920`, `src-tauri/src/lib.rs:269/280/72`

The X handler does `hide()` then `setEnabled(false)`. Only a **left-click** on the tray icon calls `set_enabled(true)`. The tray context-menu "Show" item and the single-instance restore handler (deep link / second launch) call `show()`/`set_focus()` but never `set_enabled(true)`, so the window reappears fully frozen to mouse and keyboard. Recovery requires left-clicking the tray icon.

### 11. A failed shared-modpack install permanently disables the Download button
`src/components/Pages/ShareSyncPage/SharePage.tsx:74`

`installRemoteModpack` refuses to run unless `progress === 1`, but the backend only emits `ModpackDownloadProgress(1.0)` on success. On any mod-download failure the catch block never resets `progress`, so it stays stuck (e.g. "43.00%", `cursor-not-allowed`) and every retry click early-returns. The user must navigate away to force a remount.

---

## 🟡 Medium (confirmed)

**Panics on valid external data (`unwrap`/`expect`/slice):**
- `curseforge.rs:83` — `From<ModFile>` `.expect`s a sha1 hash that CurseForge files can lack.
- `curseforge.rs:501` / `:506` — `identify_modpack_curseforge` unwraps on fingerprint matches lacking a sha1 or with no local counterpart.
- `account/id.rs:524`, `account/quadrant_share.rs:81` — `response_preview` slices an error body at byte 300, panicking on a multi-byte UTF-8 boundary.

**Filesystem / install correctness:**
- `modpacks.rs:462` — manifest is written and existing mod files deleted **before** downloads complete, corrupting an applied modpack if any download fails.
- `modpacks.rs:461` — cleanup deletes `quadrantSync.json` and any untracked file (wiping sync metadata), and errors on subdirectories.
- `modpacks.rs:369` — `delete_mod` arbitrary-delete via the same decoded `download_url` filename (the deletion half of finding #1).
- `modpacks.rs:380` — `delete_mod` fails to remove a mod entry if its jar is already missing on disk.
- `modpacks.rs:202` — renaming an applied modpack leaves a dangling `mods` symlink; `apply_modpack` then always fails with `AlreadyExists`.
- `src/components/shared/Mod.tsx:250` — update flow deletes the installed mod from disk **before** the replacement downloads; a failed install loses the mod.
- `cache.rs:56` — `init_cache` permanently fails (bricking all downloads) if a stale cache entry's file was already deleted.
- `cache.rs:129` — cache filename collision overwrites another hash's file, serving wrong content.

**Network / query building:**
- `curseforge.rs:249`, `modrinth.rs:56` — search text is interpolated into the URL unencoded; `&` or `#` corrupts/truncates the request.

**Sync / host state:**
- `quadrant-host/src/lib.rs:1600` — `maybe_backfill_local_modpack_id` overwrites a different modpack's id, letting a same-named cloud pack hijack an unrelated local one.
- `quadrant-host/src/lib.rs:1633` — remote auto-update installs into a folder named after the *remote* pack but stamps sync metadata onto the *local* pack.
- `quadrant-host/src/lib.rs:1635/1644` — the `updated_modpacks` guard leaks on malformed payload / metadata-write error, permanently disabling auto-sync until restart.
- `quadrant-host/src/lib.rs:899` — `share_modpack_raw` returns an error after a *successful* share if the follow-up telemetry POST fails.

**Security / privacy:**
- `src/components/shared/Notifications.tsx:412` + `src-tauri/tauri.conf.json:31` — RSS article summaries are injected via `dangerouslySetInnerHTML` while CSP is `null`; remote feed HTML/script runs inside the privileged webview (stored-XSS surface). Sanitize the HTML and set a real CSP.
- `src/components/Pages/ShareSyncPage/SyncedModpack/SyncedModpack.tsx:189` — Kick button shown to every non-self member (always-true object comparison, missing admin check).
- `src-tauri/src/other/telemetry.rs:20` — `remove_telemetry` swallows failures, so users are told their telemetry was deleted when it may not have been.
- `src-tauri/src/lib.rs:164` — autostart is force-enabled on every launch with no opt-out.

**Frontend UX / async:**
- `SearchPage.tsx:128` — concurrent searches have no cancellation; a slow earlier search overwrites a newer one's results.
- `SearchPage.tsx:426` — changing loader/version/modpack while a filter is active never re-runs the search.
- `SearchPage.tsx:223`, `SharePage.tsx:68` — search / fetch-by-code failures are unhandled (infinite spinner / silent no-op).
- `ModInstallPage.tsx:83` — install-progress listeners are never unsubscribed, leaking a handler on every visit.
- `AccountPage.tsx:184` — OAuth sign-in leaks its listener + local server on abandonment; a retry registers duplicate racing handlers.
- `src/tools.ts:35` — `applyModpack` swallows all errors, so a failed apply looks like success.
- `src/components/core/LinearProgress.tsx:20` — width is a runtime Tailwind arbitrary class that JIT never emits, so the bar is always full.
- `SharePage.tsx:49` — a second shared-modpack deep link is silently ignored; stale pack shown.

**Update channel:**
- `src-tauri/src/lib.rs:427` — non-stable update endpoint omits the `?variant={{bundle_type}}` query the stable endpoint sends.

**Packaging / CI:**
- `dev.mrquantumoff.mcmodpackmanager.yml:11` — Flatpak manifest launches `quadrant-next`, but the deb ships `quadrant_next` (won't start).
- `AppxManifest.xml:15` — MSIX Identity Version hardcoded `26.7.0.0`, never synced to the tag → stale/duplicate Store submissions.
- `msixbuild.ps1:125` — `$sourceExe` can be `$null` → `Test-Path` throws a terminating error instead of skipping a missing architecture.
- `.github/workflows/validate-desktop.yml:46` — "Validate Desktop" never validates `metainfo.xml`/`.desktop`; broken AppStream metadata passes vacuously.

---

## ⚪ Low (confirmed)

- `curseforge.rs:382` — DateTime `.unwrap()` inside a sort comparator panics on any non-RFC3339 `fileDate`.
- `curseforge.rs:246` — duplicate of the unencoded-search-query issue.
- `modrinth.rs:307` — returns `noVersion` when no file has `primary=true`.
- `modrinth.rs:68` — HTTP status never checked; rate-limit responses parse as empty success.
- `modrinth.rs:169` — reads `license` with `as_str()` but the endpoint returns an object.
- `mod.rs:576` — `install_local_file` `expect()`-panics when `mod_type=Mod` and modpack is `None` instead of returning the intended error.
- `modpacks.rs:195` — Windows `apply_modpack` fallback removes a non-existent path and recurses with no success path.
- `Apply.tsx:129` — watcher callback captures a stale `updateModpacks`, resetting the list to unfiltered.
- `Apply.tsx:240` — Clear button dereferences `versions[0]` unguarded after deleting the "free" modpack.
- `App.tsx:240` — download-progress handler treats a 0..1 fraction as a percent (taskbar bar shows ~0 %).
- `App.tsx:326` — CurseForge deep-link guard tests for `"/install\\"`, which can never appear.
- `App.tsx:312` — deep-link handler has no error handling (unhandled rejections).
- `App.tsx:786` — snackbar auto-hide timer isn't restarted when a same-timeout snackbar replaces a visible one.
- `App.tsx:627` — deep-link listener captures a first-render closure where `isLinux` is still false, bypassing the Linux opt-out.
- `src-tauri/src/lib.rs:462` — update-progress callback `content_length.unwrap()` panics when no Content-Length.
- `src-tauri/src/lib.rs:169` — `setup()` panics on `is_enabled().unwrap()`, aborting startup if the autostart query fails.
- `quadrant-host/src/lib.rs:1508` — `build_notification_ws_url` hardcodes `/api/v3`, breaking the WS for a custom `api-url`.
- `Notifications.tsx:324` — notification read/accept/decline have no error handling.
- `SharePage.tsx:33` — `isLoading` is never set true; the spinner is dead code.
- `Settings.tsx:137` — `t("locale")` key is missing from all three locales; literal `"locale"` used as the aria-label.
- `src-tauri/src/mc_mod/cache.rs` & `curseforge_fingerprint.rs` — dead duplicate files never declared as modules.
- `dev.mrquantumoff.mcmodpackmanager.metainfo.xml:392` — duplicate `<release>` entries (24.12.1 and 24.5.0-preview each listed twice).

---

## Plausible (one of two verifiers confirmed — worth a look)

- `modrinth.rs:150` — `get_mod_modrinth` uses `versions.first()`, which is the *oldest* version id, not the latest.
- `ModInstallPage.tsx:338` — Download button has no in-flight guard → duplicate concurrent installs on double-click.
- `src/tools.ts:146` — `getModOwners`/`getModDependencies` use `else if (ModSource.Modrinth)` (a truthy constant) rather than comparing against the source.
- `App.tsx:701` — `changePage` sets `content` without updating `page`.
- `account/quadrant_settings_sync.rs:77` — cloud settings re-applied every cycle because `lastSettingsUpdated` isn't advanced after applying.
- `account/quadrant_settings_sync.rs:73/22` — applies every cloud key (not just `SYNCED_KEYS`); `hardwareId` is in `SYNCED_KEYS`, replicating one machine's "stable installation id" everywhere.
- `telemetry.rs:98` — `send_telemetry` defaults to *sending* when `collectUserData` is absent.
- `rss.rs:21` — one malformed `pubDate` fails the entire news feed.
- `.github/workflows/release.yml:116` — `submit_update` guard is a De Morgan tautology (always true).
