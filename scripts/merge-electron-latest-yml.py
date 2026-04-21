#!/usr/bin/env python3

from __future__ import annotations

import argparse
import copy
import re
from datetime import datetime
from pathlib import Path
from typing import Any

import yaml

ARCH_ALIASES = {
    "x64": ("x64", "x86_64", "amd64"),
    "arm64": ("arm64", "aarch64", "arm"),
}


def load_metadata(path: Path) -> dict[str, Any]:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{path} did not contain a YAML object")
    return data


def extract_files(metadata: dict[str, Any]) -> list[dict[str, Any]]:
    files = metadata.get("files")
    if isinstance(files, list) and files:
        return [copy.deepcopy(item) for item in files if isinstance(item, dict)]

    path = metadata.get("path")
    sha512 = metadata.get("sha512")
    if not path or not sha512:
        raise ValueError("metadata must contain either a non-empty files list or path/sha512 fields")

    file_info: dict[str, Any] = {"url": path, "sha512": sha512}
    for key in ("size", "blockMapSize"):
        value = metadata.get(key)
        if value is not None:
            file_info[key] = value
    return [file_info]


def normalize_arch(arch: str) -> str:
    normalized = arch.strip().lower()
    for canonical, aliases in ARCH_ALIASES.items():
        if normalized == canonical or normalized in aliases:
            return canonical
    raise ValueError(
        f"unsupported architecture {arch!r}; "
        f"expected one of {', '.join(ARCH_ALIASES)}",
    )


def tokenize_artifact_name(value: str) -> set[str]:
    return {token for token in re.split(r"[^a-z0-9_]+", value.lower()) if token}


def file_matches_arch(file_info: dict[str, Any], arch: str) -> bool:
    url = file_info.get("url")
    if not isinstance(url, str):
        return False

    tokens = tokenize_artifact_name(url)
    aliases = ARCH_ALIASES[normalize_arch(arch)]
    return any(alias in tokens for alias in aliases)


def find_file_for_arch(
    files: list[dict[str, Any]],
    arch: str,
) -> dict[str, Any] | None:
    return next(
        (file_info for file_info in files if file_matches_arch(file_info, arch)),
        None,
    )


def validate_required_arches(
    files: list[dict[str, Any]],
    required_arches: list[str],
) -> None:
    missing = [
        arch
        for arch in [normalize_arch(value) for value in required_arches]
        if find_file_for_arch(files, arch) is None
    ]
    if missing:
        urls = [file_info.get("url") for file_info in files]
        raise ValueError(
            f"merged metadata is missing update files for: {', '.join(missing)}. "
            f"Found files: {urls!r}",
        )


def merge_files(base: dict[str, Any], extra: dict[str, Any]) -> list[dict[str, Any]]:
    merged: dict[str, dict[str, Any]] = {}

    for metadata in (base, extra):
        for file_info in extract_files(metadata):
            url = file_info.get("url")
            if not isinstance(url, str) or not url:
                raise ValueError(f"invalid file entry without a url: {file_info!r}")
            existing = merged.get(url)
            if existing is not None and existing != file_info:
                raise ValueError(f"conflicting file metadata for {url}")
            merged[url] = file_info

    return list(merged.values())


def apply_legacy_top_level_file_fields(
    merged: dict[str, Any],
    files: list[dict[str, Any]],
) -> None:
    # electron-updater 2.15+ reads `files`, but keep old path/sha512 fields coherent.
    canonical_file = find_file_for_arch(files, "x64") or files[0]
    url = canonical_file.get("url")
    sha512 = canonical_file.get("sha512")
    if isinstance(url, str) and url:
        merged["path"] = url
    if isinstance(sha512, str) and sha512:
        merged["sha512"] = sha512

    for key in ("size", "blockMapSize"):
        value = canonical_file.get(key)
        if value is not None:
            merged[key] = value
        elif key in merged:
            del merged[key]


def merge_packages(base: dict[str, Any], extra: dict[str, Any]) -> dict[str, Any] | None:
    merged: dict[str, Any] = {}

    for metadata in (base, extra):
        packages = metadata.get("packages")
        if packages is None:
            continue
        if not isinstance(packages, dict):
            raise ValueError("packages must be a mapping when present")
        for arch, package_info in packages.items():
            existing = merged.get(arch)
            if existing is not None and existing != package_info:
                raise ValueError(f"conflicting package metadata for architecture {arch}")
            merged[arch] = copy.deepcopy(package_info)

    return merged or None


def merge_release_date(base: dict[str, Any], extra: dict[str, Any]) -> str | None:
    candidates = []
    for metadata in (base, extra):
        release_date = metadata.get("releaseDate")
        if isinstance(release_date, str):
            candidates.append(release_date)

    if not candidates:
        return None

    try:
        return max(candidates, key=lambda value: datetime.fromisoformat(value.replace("Z", "+00:00")))
    except ValueError:
        return candidates[0]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Merge two electron-builder update metadata files into one Windows latest.yml",
    )
    parser.add_argument("--base", required=True, help="The primary metadata file, usually x64 latest.yml")
    parser.add_argument("--extra", required=True, help="The secondary metadata file to merge in, usually arm64 latest.yml")
    parser.add_argument("--output", required=True, help="Path to the merged YAML file")
    parser.add_argument(
        "--require-arch",
        action="append",
        default=None,
        help="Require an update artifact for this architecture in the merged metadata. Can be repeated.",
    )
    args = parser.parse_args()

    base_path = Path(args.base)
    extra_path = Path(args.extra)
    output_path = Path(args.output)

    base = load_metadata(base_path)
    extra = load_metadata(extra_path)

    base_version = base.get("version")
    extra_version = extra.get("version")
    if base_version != extra_version:
        raise ValueError(
            f"refusing to merge metadata from different versions: {base_version!r} != {extra_version!r}",
        )

    merged = copy.deepcopy(base)
    files = merge_files(base, extra)
    validate_required_arches(files, args.require_arch or ["x64", "arm64"])
    merged["files"] = files
    apply_legacy_top_level_file_fields(merged, files)

    packages = merge_packages(base, extra)
    if packages is not None:
        merged["packages"] = packages
    elif "packages" in merged:
        del merged["packages"]

    release_date = merge_release_date(base, extra)
    if release_date is not None:
        merged["releaseDate"] = release_date

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        yaml.safe_dump(merged, sort_keys=False, allow_unicode=False),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
