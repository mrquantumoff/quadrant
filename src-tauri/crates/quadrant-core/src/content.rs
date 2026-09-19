//! The resource packs and shader packs installed in a game directory: listing
//! them, copying them into another game directory, and deleting them.
//!
//! A game directory is either the Minecraft folder or a Prism Launcher
//! instance's, so a location is identified by a string a host can hand back
//! later ([`parse_location_id`]) instead of by a filesystem path.

use crate::{
    Result, error::ErrorCode, mc_mod::ModType, models::is_single_path_component,
    modpacks::write_atomically,
};
use serde::{Deserialize, Serialize};
use std::{
    fs::Metadata,
    path::{Path, PathBuf},
    time::UNIX_EPOCH,
};

const RESOURCE_PACKS_DIR: &str = "resourcepacks";
const SHADER_PACKS_DIR: &str = "shaderpacks";

/// Identifier of the Minecraft folder as a content location.
pub const MINECRAFT_LOCATION_ID: &str = "minecraft";

const PRISM_LOCATION_PREFIX: &str = "prism:";

/// One installed resource pack or shader pack, as it sits on disk.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ContentFile {
    pub file_name: String,
    /// Size in bytes, `0` for a directory.
    pub size: u64,
    /// Modification time in milliseconds since the epoch, `0` when unknown.
    pub modified: i64,
    pub is_directory: bool,
}

/// Which launcher owns a content location.
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ContentLocationKind {
    Minecraft,
    Prism,
}

/// A game directory and everything installed in it.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ContentLocation {
    /// [`MINECRAFT_LOCATION_ID`], or the [`prism_location_id`] of an instance.
    pub id: String,
    pub kind: ContentLocationKind,
    /// Display name, empty for the Minecraft folder so a frontend localizes it.
    pub name: String,
    pub path: String,
    pub resource_packs: Vec<ContentFile>,
    pub shader_packs: Vec<ContentFile>,
}

/// What a [`ContentLocation::id`] points at.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LocationRef<'a> {
    Minecraft,
    Prism(&'a str),
}

/// The location id of a Prism instance.
pub fn prism_location_id(instance_id: &str) -> String {
    format!("{PRISM_LOCATION_PREFIX}{instance_id}")
}

/// Reads a location id, or `None` when it names neither the Minecraft folder
/// nor an instance.
pub fn parse_location_id(id: &str) -> Option<LocationRef<'_>> {
    if id == MINECRAFT_LOCATION_ID {
        return Some(LocationRef::Minecraft);
    }
    id.strip_prefix(PRISM_LOCATION_PREFIX)
        .filter(|instance_id| !instance_id.is_empty())
        .map(LocationRef::Prism)
}

/// The folder of a game directory `mod_type` is installed into, if it has one.
pub fn content_subfolder(mod_type: ModType) -> Option<&'static str> {
    match mod_type {
        ModType::ResourcePack => Some(RESOURCE_PACKS_DIR),
        ModType::ShaderPack => Some(SHADER_PACKS_DIR),
        _ => None,
    }
}

/// Lists what is installed in one folder, sorted case-insensitively by name.
///
/// A folder that is missing or cannot be read is an empty list rather than an
/// error, because a game directory only grows these folders once something is
/// installed into it. Only directories and `.zip` files are kept, which drops
/// the sidecar files a shader loader writes next to a pack.
pub fn list_content_files(dir: &Path) -> Vec<ContentFile> {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return Vec::new();
    };

    let mut files: Vec<ContentFile> = entries
        .filter_map(|entry| {
            let entry = entry.ok()?;
            let file_name = entry.file_name().to_string_lossy().into_owned();
            // Through the path, not the entry, so a symlinked pack is measured
            // by what it points at.
            let metadata = entry.path().metadata().ok()?;
            if !is_listed_pack(&file_name, &metadata) {
                return None;
            }
            let is_directory = metadata.is_dir();
            Some(ContentFile {
                file_name,
                size: if is_directory { 0 } else { metadata.len() },
                modified: modified_millis(&metadata),
                is_directory,
            })
        })
        .collect();

    files.sort_by_key(|file| file.file_name.to_lowercase());
    files
}

/// Whether an entry is a pack at all: a directory or a `.zip`, never one of the
/// sidecar or dotfiles that sit beside the packs. The single rule behind both
/// what [`list_content_files`] shows and what [`copy_content_files`] accepts.
fn is_listed_pack(file_name: &str, metadata: &Metadata) -> bool {
    !file_name.starts_with('.') && (metadata.is_dir() || file_name.to_lowercase().ends_with(".zip"))
}

fn modified_millis(metadata: &Metadata) -> i64 {
    metadata
        .modified()
        .ok()
        .and_then(|modified| modified.duration_since(UNIX_EPOCH).ok())
        .and_then(|since_epoch| i64::try_from(since_epoch.as_millis()).ok())
        .unwrap_or(0)
}

/// Reads the resource packs and shader packs installed in a game directory.
pub fn content_location(
    id: &str,
    kind: ContentLocationKind,
    name: &str,
    game_dir: &Path,
) -> ContentLocation {
    ContentLocation {
        id: id.to_string(),
        kind,
        name: name.to_string(),
        path: game_dir.to_string_lossy().into_owned(),
        resource_packs: list_content_files(&game_dir.join(RESOURCE_PACKS_DIR)),
        shader_packs: list_content_files(&game_dir.join(SHADER_PACKS_DIR)),
    }
}

/// Copies the named packs from one folder to another, returning how many were
/// copied.
///
/// Every name is resolved before anything is written, so a bad name anywhere in
/// the batch leaves the destination untouched. Copying is idempotent: an entry
/// that already exists in `to_dir` is overwritten rather than refused.
pub fn copy_content_files(from_dir: &Path, to_dir: &Path, file_names: &[String]) -> Result<usize> {
    if is_same_dir(from_dir, to_dir) {
        return Err(anyhow::Error::from(ErrorCode::InvalidRequest));
    }
    let packs = file_names
        .iter()
        .map(|file_name| resolve_pack(from_dir, file_name))
        .collect::<Result<Vec<_>>>()?;

    std::fs::create_dir_all(to_dir)?;
    for (file_name, (source, is_directory)) in file_names.iter().zip(&packs) {
        let target = to_dir.join(file_name);
        if *is_directory {
            copy_dir_into(source, &target)?;
        } else {
            copy_file_atomically(source, &target)?;
        }
    }
    Ok(packs.len())
}

/// Locates one pack to copy, refusing a name that is not a single path
/// component or does not name something [`list_content_files`] would list.
fn resolve_pack(from_dir: &Path, file_name: &str) -> Result<(PathBuf, bool)> {
    if !is_single_path_component(file_name) {
        return Err(anyhow::Error::from(ErrorCode::InvalidRequest));
    }
    let source = from_dir.join(file_name);
    let metadata = source.metadata().map_err(|_| ErrorCode::ContentMissing)?;
    if !is_listed_pack(file_name, &metadata) {
        return Err(anyhow::Error::from(ErrorCode::ContentMissing));
    }
    Ok((source, metadata.is_dir()))
}

/// Permanently removes the named packs from a folder, returning how many were
/// removed.
///
/// Every name is resolved before anything is removed, so a bad name anywhere in
/// the batch leaves the folder untouched. A name that is already gone is
/// skipped rather than refused, so retrying after a partial failure converges
/// on the same folder instead of erroring on what the first run removed.
pub fn delete_content_files(dir: &Path, file_names: &[String]) -> Result<usize> {
    let packs = file_names
        .iter()
        .map(|file_name| resolve_pack_to_delete(dir, file_name))
        .collect::<Result<Vec<_>>>()?;

    let mut removed = 0;
    for pack in packs.into_iter().flatten() {
        remove_pack(&pack)?;
        removed += 1;
    }
    Ok(removed)
}

/// Locates one pack to delete, or `None` when nothing by that name is there.
///
/// Kept apart from [`resolve_pack`] because the two disagree on purpose about a
/// name that is missing: copying it is a request that cannot be served, while
/// deleting it is already done.
fn resolve_pack_to_delete(dir: &Path, file_name: &str) -> Result<Option<PathBuf>> {
    if !is_single_path_component(file_name) {
        return Err(anyhow::Error::from(ErrorCode::InvalidRequest));
    }
    let path = dir.join(file_name);
    let Ok(link_metadata) = path.symlink_metadata() else {
        return Ok(None);
    };
    // Classified by what a link points at, the way the listing shows it, even
    // though it is the link itself that gets removed. A broken link has only
    // its own metadata to go on, which leaves the `.zip` suffix deciding.
    let metadata = path.metadata().unwrap_or(link_metadata);
    if !is_listed_pack(file_name, &metadata) {
        return Err(anyhow::Error::from(ErrorCode::ContentMissing));
    }
    Ok(Some(path))
}

fn remove_pack(path: &Path) -> Result<()> {
    let file_type = path.symlink_metadata()?.file_type();
    if file_type.is_symlink() {
        // Removing the link, never what it points at: a pack linked in from
        // elsewhere is unlinked from this game directory, not deleted from disk.
        remove_symlink(path, &file_type)?;
    } else if file_type.is_dir() {
        std::fs::remove_dir_all(path)?;
    } else {
        std::fs::remove_file(path)?;
    }
    Ok(())
}

#[cfg(windows)]
fn remove_symlink(path: &Path, file_type: &std::fs::FileType) -> std::io::Result<()> {
    use std::os::windows::fs::FileTypeExt;
    if file_type.is_symlink_dir() {
        std::fs::remove_dir(path)
    } else {
        std::fs::remove_file(path)
    }
}

#[cfg(not(windows))]
fn remove_symlink(path: &Path, _file_type: &std::fs::FileType) -> std::io::Result<()> {
    std::fs::remove_file(path)
}

/// Whether both paths name the same folder, so that copying a pack onto itself
/// is caught however each side spells the path.
fn is_same_dir(from_dir: &Path, to_dir: &Path) -> bool {
    match (from_dir.canonicalize(), to_dir.canonicalize()) {
        (Ok(from_dir), Ok(to_dir)) => from_dir == to_dir,
        _ => from_dir == to_dir,
    }
}

fn copy_file_atomically(source: &Path, target: &Path) -> Result<()> {
    let mut reader = std::fs::File::open(source)?;
    write_atomically(target, |file| std::io::copy(&mut reader, file).map(|_| ()))?;
    Ok(())
}

fn copy_dir_into(source: &Path, target: &Path) -> Result<()> {
    std::fs::create_dir_all(target)?;
    for entry in std::fs::read_dir(source)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        // A link inside a pack can point anywhere on disk, and following it
        // would copy whatever it reaches into the other game directory.
        if file_type.is_symlink() {
            log::warn!(
                "Skipping symlinked entry \"{}\" while copying a pack",
                entry.path().display()
            );
            continue;
        }
        let entry_target = target.join(entry.file_name());
        if file_type.is_dir() {
            copy_dir_into(&entry.path(), &entry_target)?;
        } else {
            std::fs::copy(entry.path(), &entry_target)?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::{TempDir, tempdir};

    fn names(files: &[ContentFile]) -> Vec<&str> {
        files.iter().map(|file| file.file_name.as_str()).collect()
    }

    fn pack_folders() -> (TempDir, PathBuf, PathBuf) {
        let dir = tempdir().unwrap();
        let from_dir = dir.path().join("minecraft").join(RESOURCE_PACKS_DIR);
        let to_dir = dir.path().join("instance").join(RESOURCE_PACKS_DIR);
        std::fs::create_dir_all(&from_dir).unwrap();
        (dir, from_dir, to_dir)
    }

    #[test]
    fn list_content_files_keeps_packs_and_drops_everything_else() {
        let dir = tempdir().unwrap();
        let packs = dir.path().join("resourcepacks");
        std::fs::create_dir_all(packs.join("Unzipped Pack")).unwrap();
        std::fs::create_dir_all(packs.join(".cache")).unwrap();
        std::fs::write(packs.join("zebra.zip"), "1234").unwrap();
        std::fs::write(packs.join("Alpha.ZIP"), "12").unwrap();
        std::fs::write(packs.join("Foo.zip.txt"), "options").unwrap();
        std::fs::write(packs.join(".hidden.zip"), "hidden").unwrap();
        std::fs::write(packs.join("readme.md"), "notes").unwrap();

        let files = list_content_files(&packs);

        assert_eq!(names(&files), ["Alpha.ZIP", "Unzipped Pack", "zebra.zip"]);
        assert_eq!(files[0].size, 2);
        assert!(!files[0].is_directory);
        assert!(files[0].modified > 0);
        assert_eq!(files[1].size, 0);
        assert!(files[1].is_directory);
    }

    #[test]
    fn list_content_files_treats_a_missing_folder_as_empty() {
        let dir = tempdir().unwrap();
        assert!(list_content_files(&dir.path().join("shaderpacks")).is_empty());
        // A file where the folder should be is unreadable as a directory.
        let file = dir.path().join("resourcepacks");
        std::fs::write(&file, "not a folder").unwrap();
        assert!(list_content_files(&file).is_empty());
    }

    #[test]
    fn content_location_reads_both_folders() {
        let dir = tempdir().unwrap();
        let game_dir = dir.path().join("minecraft");
        std::fs::create_dir_all(game_dir.join("resourcepacks")).unwrap();
        std::fs::create_dir_all(game_dir.join("shaderpacks")).unwrap();
        std::fs::write(game_dir.join("resourcepacks").join("pack.zip"), "pack").unwrap();
        std::fs::write(game_dir.join("shaderpacks").join("shader.zip"), "shader").unwrap();

        let location = content_location(
            MINECRAFT_LOCATION_ID,
            ContentLocationKind::Minecraft,
            "",
            &game_dir,
        );

        assert_eq!(location.id, MINECRAFT_LOCATION_ID);
        assert_eq!(location.kind, ContentLocationKind::Minecraft);
        assert_eq!(location.name, "");
        assert_eq!(location.path, game_dir.to_string_lossy());
        assert_eq!(names(&location.resource_packs), ["pack.zip"]);
        assert_eq!(names(&location.shader_packs), ["shader.zip"]);
    }

    #[test]
    fn location_ids_round_trip() {
        assert_eq!(
            parse_location_id(MINECRAFT_LOCATION_ID),
            Some(LocationRef::Minecraft)
        );
        for instance_id in ["alpha", "1.21.1: Fabric", "../escape"] {
            assert_eq!(
                parse_location_id(&prism_location_id(instance_id)),
                Some(LocationRef::Prism(instance_id))
            );
        }
        for id in ["", "prism", "prism:", "Minecraft", "minecraft:alpha"] {
            assert_eq!(parse_location_id(id), None, "{id:?}");
        }
    }

    #[test]
    fn copy_content_files_copies_zips_and_folders_into_a_new_folder() {
        let (_dir, from_dir, to_dir) = pack_folders();
        let zip: Vec<u8> = (0..=255u8).cycle().take(5000).collect();
        std::fs::write(from_dir.join("Faithful.zip"), &zip).unwrap();
        let assets = from_dir.join("Unzipped").join("assets").join("minecraft");
        std::fs::create_dir_all(&assets).unwrap();
        std::fs::write(from_dir.join("Unzipped").join("pack.mcmeta"), "meta").unwrap();
        std::fs::write(assets.join("grass.png"), "png").unwrap();

        let copied = copy_content_files(
            &from_dir,
            &to_dir,
            &["Faithful.zip".to_string(), "Unzipped".to_string()],
        )
        .unwrap();

        assert_eq!(copied, 2);
        assert_eq!(std::fs::read(to_dir.join("Faithful.zip")).unwrap(), zip);
        assert_eq!(
            std::fs::read_to_string(to_dir.join("Unzipped").join("pack.mcmeta")).unwrap(),
            "meta"
        );
        assert_eq!(
            std::fs::read_to_string(
                to_dir
                    .join("Unzipped")
                    .join("assets")
                    .join("minecraft")
                    .join("grass.png")
            )
            .unwrap(),
            "png"
        );
        // The temp file the zip was streamed through is gone.
        assert_eq!(
            names(&list_content_files(&to_dir)),
            ["Faithful.zip", "Unzipped"]
        );
        assert_eq!(std::fs::read_dir(&to_dir).unwrap().count(), 2);
    }

    #[test]
    fn copying_the_same_packs_again_overwrites_the_destination() {
        let (_dir, from_dir, to_dir) = pack_folders();
        std::fs::write(from_dir.join("pack.zip"), "new").unwrap();
        std::fs::create_dir_all(from_dir.join("folder")).unwrap();
        std::fs::write(from_dir.join("folder").join("pack.mcmeta"), "new").unwrap();
        std::fs::create_dir_all(to_dir.join("folder")).unwrap();
        std::fs::write(to_dir.join("pack.zip"), "stale and much longer").unwrap();
        std::fs::write(to_dir.join("folder").join("pack.mcmeta"), "stale").unwrap();
        std::fs::write(to_dir.join("folder").join("extra.png"), "kept").unwrap();

        let file_names = ["pack.zip".to_string(), "folder".to_string()];
        assert_eq!(
            copy_content_files(&from_dir, &to_dir, &file_names).unwrap(),
            2
        );
        assert_eq!(
            copy_content_files(&from_dir, &to_dir, &file_names).unwrap(),
            2
        );

        assert_eq!(
            std::fs::read_to_string(to_dir.join("pack.zip")).unwrap(),
            "new"
        );
        assert_eq!(
            std::fs::read_to_string(to_dir.join("folder").join("pack.mcmeta")).unwrap(),
            "new"
        );
        assert_eq!(
            std::fs::read_to_string(to_dir.join("folder").join("extra.png")).unwrap(),
            "kept"
        );
    }

    #[test]
    fn copy_content_files_rejects_unsafe_names_before_writing_anything() {
        let (_dir, from_dir, to_dir) = pack_folders();
        std::fs::write(from_dir.join("good.zip"), "pack").unwrap();
        let absolute = if cfg!(windows) {
            "C:\\windows\\system32"
        } else {
            "/etc/passwd"
        };

        for file_name in ["../escape", "a/b", absolute, "", ".", ".."] {
            let file_names = ["good.zip".to_string(), file_name.to_string()];
            assert!(
                copy_content_files(&from_dir, &to_dir, &file_names)
                    .unwrap_err()
                    .to_string()
                    .contains("errorInvalidRequest"),
                "{file_name:?}"
            );
            assert!(!to_dir.exists(), "{file_name:?}");
        }
    }

    #[test]
    fn copy_content_files_refuses_names_that_are_not_installed_packs() {
        let (_dir, from_dir, to_dir) = pack_folders();
        std::fs::write(from_dir.join("good.zip"), "pack").unwrap();
        std::fs::write(from_dir.join("Foo.zip.txt"), "options").unwrap();
        std::fs::write(from_dir.join(".hidden.zip"), "hidden").unwrap();

        for file_name in ["ghost.zip", "Foo.zip.txt", ".hidden.zip"] {
            let file_names = ["good.zip".to_string(), file_name.to_string()];
            assert!(
                copy_content_files(&from_dir, &to_dir, &file_names)
                    .unwrap_err()
                    .to_string()
                    .contains("errorContentMissing"),
                "{file_name:?}"
            );
            assert!(!to_dir.exists(), "{file_name:?}");
        }
    }

    #[test]
    fn copy_content_files_refuses_a_copy_into_the_source_folder() {
        let (_dir, from_dir, _to_dir) = pack_folders();
        std::fs::write(from_dir.join("pack.zip"), "pack").unwrap();
        let file_names = ["pack.zip".to_string()];

        for to_dir in [
            from_dir.clone(),
            from_dir.join("..").join(RESOURCE_PACKS_DIR),
        ] {
            assert!(
                copy_content_files(&from_dir, &to_dir, &file_names)
                    .unwrap_err()
                    .to_string()
                    .contains("errorInvalidRequest"),
                "{}",
                to_dir.display()
            );
        }
    }

    #[test]
    fn delete_content_files_removes_packs_and_counts_what_it_removed() {
        let (_dir, dir, _to_dir) = pack_folders();
        std::fs::write(dir.join("Faithful.zip"), "pack").unwrap();
        std::fs::create_dir_all(dir.join("Unzipped").join("assets")).unwrap();
        std::fs::write(dir.join("Unzipped").join("pack.mcmeta"), "meta").unwrap();
        std::fs::write(dir.join("keep.zip"), "kept").unwrap();

        let file_names = ["Faithful.zip".to_string(), "Unzipped".to_string()];
        assert_eq!(delete_content_files(&dir, &file_names).unwrap(), 2);
        assert_eq!(names(&list_content_files(&dir)), ["keep.zip"]);

        // A second run has nothing left to remove and says so.
        assert_eq!(delete_content_files(&dir, &file_names).unwrap(), 0);
        assert_eq!(names(&list_content_files(&dir)), ["keep.zip"]);
    }

    #[test]
    fn delete_content_files_skips_names_that_are_already_gone() {
        let (_dir, dir, _to_dir) = pack_folders();
        std::fs::write(dir.join("keep.zip"), "kept").unwrap();

        assert_eq!(
            delete_content_files(&dir, &["ghost.zip".to_string()]).unwrap(),
            0
        );
        assert_eq!(names(&list_content_files(&dir)), ["keep.zip"]);
    }

    #[test]
    fn delete_content_files_refuses_anything_that_is_not_an_installed_pack() {
        let (_dir, dir, _to_dir) = pack_folders();
        std::fs::write(dir.join("good.zip"), "pack").unwrap();
        std::fs::write(dir.join("Foo.zip.txt"), "options").unwrap();
        std::fs::write(dir.join("options.txt"), "settings").unwrap();
        std::fs::write(dir.join(".hidden.zip"), "hidden").unwrap();

        for file_name in ["Foo.zip.txt", "options.txt", ".hidden.zip"] {
            let file_names = ["good.zip".to_string(), file_name.to_string()];
            assert!(
                delete_content_files(&dir, &file_names)
                    .unwrap_err()
                    .to_string()
                    .contains("errorContentMissing"),
                "{file_name:?}"
            );
            assert!(dir.join(file_name).exists(), "{file_name:?}");
            assert!(dir.join("good.zip").exists(), "{file_name:?}");
        }
    }

    #[test]
    fn delete_content_files_rejects_unsafe_names_before_removing_anything() {
        let (_dir, dir, _to_dir) = pack_folders();
        std::fs::write(dir.join("good.zip"), "pack").unwrap();
        let outside = dir.join("..").join("secrets.zip");
        std::fs::write(&outside, "secrets").unwrap();
        let absolute = if cfg!(windows) {
            "C:\\windows\\system32"
        } else {
            "/etc/passwd"
        };

        for file_name in ["../secrets.zip", "a/b", absolute, "", ".", ".."] {
            let file_names = ["good.zip".to_string(), file_name.to_string()];
            assert!(
                delete_content_files(&dir, &file_names)
                    .unwrap_err()
                    .to_string()
                    .contains("errorInvalidRequest"),
                "{file_name:?}"
            );
            assert!(dir.join("good.zip").exists(), "{file_name:?}");
            assert!(outside.exists(), "{file_name:?}");
        }
    }

    #[cfg(not(target_os = "windows"))]
    #[test]
    fn delete_content_files_unlinks_a_linked_pack_without_touching_its_target() {
        let (temp_dir, dir, _to_dir) = pack_folders();
        let elsewhere = temp_dir.path().join("elsewhere");
        std::fs::create_dir_all(elsewhere.join("assets")).unwrap();
        std::fs::write(elsewhere.join("pack.mcmeta"), "meta").unwrap();
        std::os::unix::fs::symlink(&elsewhere, dir.join("Linked")).unwrap();

        assert_eq!(
            delete_content_files(&dir, &["Linked".to_string()]).unwrap(),
            1
        );
        assert!(list_content_files(&dir).is_empty());
        assert!(elsewhere.join("pack.mcmeta").exists());
    }

    #[test]
    fn only_resource_packs_and_shaders_have_a_content_folder() {
        assert_eq!(
            content_subfolder(ModType::ResourcePack),
            Some(RESOURCE_PACKS_DIR)
        );
        assert_eq!(
            content_subfolder(ModType::ShaderPack),
            Some(SHADER_PACKS_DIR)
        );
        for mod_type in [
            ModType::Mod,
            ModType::Modpack,
            ModType::DataPack,
            ModType::Unknown,
        ] {
            assert_eq!(content_subfolder(mod_type), None, "{mod_type}");
        }
    }
}
