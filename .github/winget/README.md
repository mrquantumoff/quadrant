<!-- @format -->

# WinGet packaging

Manifests for the [Windows Package Manager Community Repository](https://github.com/microsoft/winget-pkgs)
(`winget install QuadrantMC.Quadrant`).

The `manifests/` tree here mirrors the winget-pkgs layout exactly, so the rendered output can be
copied straight into a winget-pkgs fork with no path rewriting.

```
manifests/q/QuadrantMC/Quadrant/<version>/
  QuadrantMC.Quadrant.yaml                 # version file
  QuadrantMC.Quadrant.locale.en-US.yaml    # default locale metadata
  QuadrantMC.Quadrant.installer.yaml       # installer URLs, hashes, switches
```

## How releases get published

`release.yml` runs the `publish_winget` job on every `-stable` tag, alongside the Flathub and AUR
jobs. It calls [`winget.yml`](../workflows/winget.yml), which:

1. Reads the installer SHA256 hashes straight from GitHub's published asset digests — the
   installers are never downloaded just to be hashed.
2. Takes the newest version folder in `manifests/` as the **base manifest** and re-renders it for
   the new version, replacing only the version string, the two hashes, and `ReleaseDate`.
   Everything else — installer switches, scope, product code, tags, description — carries forward.
3. Opens a winget-pkgs PR with `wingetcreate submit`.

This means the checked-in version folder does **not** need to be bumped every release; it is the
template the workflow renders from. Refresh it when the metadata itself changes.

Non-stable tags are refused by the workflow, so previews never reach WinGet.

### Required secret

`WINGET_TOKEN` — a classic PAT with `public_repo` scope, on an account that has a fork of
`microsoft/winget-pkgs`. `wingetcreate` pushes the branch to that fork and opens the PR from it.

### Running it manually

The workflow has a `workflow_dispatch` trigger for the first submission and for re-runs. Set
`dry_run` to render and print the manifests without opening a PR:

```bash
gh workflow run winget.yml -f tag=v26.8.0-stable -f dry_run=true
```

Or submit from a local checkout:

```bash
wingetcreate submit --token $GITHUB_TOKEN .github/winget/manifests/q/QuadrantMC/Quadrant/26.8.0-stable
```

To validate before submitting (Windows only), and optionally test the install in Windows Sandbox
with winget-pkgs' `Tools/SandboxTest.ps1`:

```bash
winget validate --manifest .github/winget/manifests/q/QuadrantMC/Quadrant/26.8.0-stable
```

## Why the manifest looks the way it does

Things that are easy to "clean up" and thereby break:

- **`PackageVersion` keeps the `-stable` suffix.** Tauri writes the full config version into the
  Add/Remove Programs `DisplayVersion` (`26.8.0-stable`). WinGet correlates the installed package
  against that string. Dropping the suffix here would make WinGet read the installed
  `26.8.0-stable` as a prerelease of `26.8.0` and offer a permanent phantom upgrade.

- **`Scope: user`.** `bundle.windows.nsis` has no `installMode`, so Tauri defaults to `currentUser`:
  installs land in `%LOCALAPPDATA%\Quadrant` with the uninstall key under `HKCU`, and no elevation
  is needed. If `installMode` ever changes to `perMachine` or `both`, this must change with it.

- **`InstallerSwitches.Upgrade: /UPDATE`.** Tauri's NSIS installer treats `/UPDATE` as
  "reinstall over an existing install": it skips the WebView2 bootstrapper and preserves shortcuts
  and the autostart registry entry. Without it, every `winget upgrade` resets start-on-login.

- **No `Silent` / `SilentWithProgress` switches.** For `InstallerType: nullsoft`, WinGet supplies
  `/S` automatically. Declaring them manually is a common review rejection.

- **`ProductCode: Quadrant`.** For a Nullsoft installer this is the Add/Remove Programs registry
  subkey name, which Tauri derives from `productName` in `tauri.conf.json`.

## Known interaction with the built-in updater

Quadrant's own updater stays enabled in WinGet installs — `resolve_autoupdate` in
`src-tauri/src/lib.rs` only disables it for `--noupdater` and msstore builds. The app therefore
updates itself ahead of whatever version WinGet knows about.

This is benign in practice: the updater re-runs the NSIS installer in passive mode, which rewrites
the same Add/Remove Programs entry, so `winget list` keeps reporting the true installed version.
It does mean WinGet is effectively install-only for this package. Disabling the updater for WinGet
installs would need either a `-winget` version suffix handled like `msstore`, or an
`nsis.installerHooks` script that records a marker the app reads at startup.
