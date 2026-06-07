#!/usr/bin/env python3

import argparse
import re
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Update the Quadrant source URLs and hashes in the Flathub manifest."
    )
    parser.add_argument("--tag", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--metainfo-sha", required=True)
    parser.add_argument("--amd64-sha", required=True)
    parser.add_argument("--arm64-sha", required=True)
    parser.add_argument("--manifest-path", required=True)
    parser.add_argument("--release-repo", default="quadrantmc/quadrant")
    return parser.parse_args()


def validate_sha(name: str, value: str) -> None:
    if not re.fullmatch(r"[0-9a-f]{64}", value):
        raise ValueError(f"{name} must be a lowercase SHA-256 hex digest")


def normalize_release_repo(value: str) -> str:
    repo = value.rstrip("/").removesuffix(".git")
    for prefix in (
        "https://github.com/",
        "http://github.com/",
        "git@github.com:",
    ):
        if repo.startswith(prefix):
            repo = repo[len(prefix) :]
            break

    repo = repo.rstrip("/")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise ValueError(
            "--release-repo must be a GitHub owner/repo or github.com URL"
        )
    return repo


def replace_unique(
    text: str,
    pattern: re.Pattern[str],
    replacement: str,
    description: str,
) -> str:
    matches = list(pattern.finditer(text))
    if len(matches) != 1:
        raise ValueError(
            f"Expected exactly one {description} block in the manifest, found {len(matches)}"
        )
    return pattern.sub(replacement, text, count=1)


def main() -> int:
    args = parse_args()

    if not args.tag.startswith("v"):
        raise ValueError("--tag must start with 'v'")

    for name, value in (
        ("--metainfo-sha", args.metainfo_sha),
        ("--amd64-sha", args.amd64_sha),
        ("--arm64-sha", args.arm64_sha),
    ):
        validate_sha(name, value)

    release_repo = normalize_release_repo(args.release_repo)

    manifest_path = Path(args.manifest_path)
    with manifest_path.open("r", encoding="utf-8", newline="") as handle:
        manifest = handle.read()

    metainfo_url = (
        f"https://github.com/{release_repo}/raw/{args.tag}/"
        "dev.mrquantumoff.mcmodpackmanager.metainfo.xml"
    )
    amd64_url = (
        f"https://github.com/{release_repo}/releases/download/{args.tag}/"
        f"Quadrant_{args.version}_amd64.deb"
    )
    arm64_url = (
        f"https://github.com/{release_repo}/releases/download/{args.tag}/"
        f"Quadrant_{args.version}_arm64.deb"
    )

    metainfo_pattern = re.compile(
        r"(?m)^(\s*-\s+type:\s+file\r?\n"
        r"\s*url:\s+)https://github\.com/[^/\r\n]+/[^/\r\n]+/raw/[^/\r\n]+/"
        r"dev\.mrquantumoff\.mcmodpackmanager\.metainfo\.xml"
        r"(\r?\n\s*sha256:\s+)[0-9a-f]{64}(\r?\n)"
    )
    amd64_pattern = re.compile(
        r"(?m)^(\s*-\s+type:\s+file\r?\n"
        r"\s*url:\s+)https://github\.com/[^/\r\n]+/[^/\r\n]+/releases/download/"
        r"[^/\r\n]+/Quadrant_[^/\r\n]+_amd64\.deb"
        r"(\r?\n\s*sha256:\s+)[0-9a-f]{64}"
        r"(\r?\n\s*only-arches:\s*\[x86_64\]\r?\n)"
    )
    arm64_pattern = re.compile(
        r"(?m)^(\s*-\s+type:\s+file\r?\n"
        r"\s*url:\s+)https://github\.com/[^/\r\n]+/[^/\r\n]+/releases/download/"
        r"[^/\r\n]+/Quadrant_[^/\r\n]+_arm64\.deb"
        r"(\r?\n\s*sha256:\s+)[0-9a-f]{64}"
        r"(\r?\n\s*only-arches:\s*\[aarch64\]\r?\n)"
    )

    updated = replace_unique(
        manifest,
        metainfo_pattern,
        rf"\g<1>{metainfo_url}\g<2>{args.metainfo_sha}\g<3>",
        "metainfo source",
    )
    updated = replace_unique(
        updated,
        amd64_pattern,
        rf"\g<1>{amd64_url}\g<2>{args.amd64_sha}\g<3>",
        "amd64 source",
    )
    updated = replace_unique(
        updated,
        arm64_pattern,
        rf"\g<1>{arm64_url}\g<2>{args.arm64_sha}\g<3>",
        "arm64 source",
    )

    with manifest_path.open("w", encoding="utf-8", newline="") as handle:
        handle.write(updated)

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
