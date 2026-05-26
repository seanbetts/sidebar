#!/usr/bin/env python3
"""Check or refresh generated Safari extension copies shared by iOS and macOS."""

from __future__ import annotations

import argparse
import filecmp
import shutil
import sys
from pathlib import Path


IOS_EXTENSION = Path("ios/sideBar/sideBar Safari Extension")
MAC_EXTENSION = Path("ios/sideBar/sideBar Safari Extension (macOS) Extension")

SHARED_SWIFT_FILES = [
    "ExtensionDiagnostics.swift",
    "SafariExtensionAuthRefresher.swift",
    "SafariWebExtensionHandler.swift",
]

IGNORED_RESOURCE_NAMES = {
    "images/logo-dark.png",
    "images/logo-light.png",
}


def emit(message: str = "") -> None:
    """Write one line to stdout."""
    sys.stdout.write(f"{message}\n")


def normalized_swift(path: Path) -> str:
    """Return Swift source with generated target-name comments normalized."""
    return "\n".join(
        line
        for line in path.read_text(encoding="utf-8").splitlines()
        if not line.startswith("//  sideBar Safari Extension")
    )


def mac_swift_copy(source: Path) -> str:
    """Return Swift source rewritten with the macOS extension target header."""
    return source.read_text(encoding="utf-8").replace(
        "//  sideBar Safari Extension\n",
        "//  sideBar Safari Extension (macOS) Extension\n",
        1,
    )


def relative_files(root: Path) -> set[str]:
    """Return relative file paths for all files under a root."""
    return {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file()
    }


def write_generated_copies(ios_root: Path, mac_root: Path) -> None:
    """Refresh macOS extension copies from the iOS extension source of truth."""
    for relative_path in SHARED_SWIFT_FILES:
        destination = mac_root / relative_path
        destination.write_text(mac_swift_copy(ios_root / relative_path), encoding="utf-8")

    ios_resources_root = ios_root / "Resources"
    mac_resources_root = mac_root / "Resources"
    shared_resources = relative_files(ios_resources_root) - IGNORED_RESOURCE_NAMES
    mac_resources = relative_files(mac_resources_root)

    for relative_path in sorted(mac_resources - shared_resources):
        (mac_resources_root / relative_path).unlink()

    for relative_path in sorted(shared_resources):
        source = ios_resources_root / relative_path
        destination = mac_resources_root / relative_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)


def parity_failures(ios_root: Path, mac_root: Path) -> list[str]:
    """Return Safari extension Swift and web-resource parity failures."""
    failures: list[str] = []

    for relative_path in SHARED_SWIFT_FILES:
        ios_path = ios_root / relative_path
        mac_path = mac_root / relative_path
        if normalized_swift(ios_path) != normalized_swift(mac_path):
            failures.append(f"Swift generated copy drifted: {relative_path}")

    ios_resources = relative_files(ios_root / "Resources") - IGNORED_RESOURCE_NAMES
    mac_resources = relative_files(mac_root / "Resources")
    if ios_resources != mac_resources:
        only_ios = sorted(ios_resources - mac_resources)
        only_mac = sorted(mac_resources - ios_resources)
        if only_ios:
            failures.append(f"Missing macOS generated resources: {', '.join(only_ios)}")
        if only_mac:
            failures.append(f"Unexpected macOS generated resources: {', '.join(only_mac)}")

    for relative_path in sorted(ios_resources & mac_resources):
        ios_path = ios_root / "Resources" / relative_path
        mac_path = mac_root / "Resources" / relative_path
        if not filecmp.cmp(ios_path, mac_path, shallow=False):
            failures.append(f"Resource generated copy drifted: {relative_path}")

    return failures


def main() -> int:
    """Check Safari extension generated-copy parity, optionally refreshing copies."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--write",
        action="store_true",
        help="Regenerate macOS Safari extension copies from the iOS source files.",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    ios_root = repo_root / IOS_EXTENSION
    mac_root = repo_root / MAC_EXTENSION

    if args.write:
        write_generated_copies(ios_root, mac_root)

    failures = parity_failures(ios_root, mac_root)

    if failures:
        emit("Safari extension generated-copy check failed:")
        for failure in failures:
            emit(f"  {failure}")
        emit("Run `python3 scripts/check_safari_extension_parity.py --write` to refresh generated copies.")
        return 1

    emit("Safari extension generated-copy check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
