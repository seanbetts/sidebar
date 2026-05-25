#!/usr/bin/env python3
"""Fail when duplicated Safari extension sources drift between iOS and macOS."""

from __future__ import annotations

import filecmp
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


def relative_files(root: Path) -> set[str]:
    """Return relative file paths for all files under a root."""
    return {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file()
    }


def main() -> int:
    """Check Safari extension Swift and web-resource parity."""
    repo_root = Path(__file__).resolve().parents[1]
    ios_root = repo_root / IOS_EXTENSION
    mac_root = repo_root / MAC_EXTENSION
    failures: list[str] = []

    for relative_path in SHARED_SWIFT_FILES:
        ios_path = ios_root / relative_path
        mac_path = mac_root / relative_path
        if normalized_swift(ios_path) != normalized_swift(mac_path):
            failures.append(f"Swift file drifted: {relative_path}")

    ios_resources = relative_files(ios_root / "Resources") - IGNORED_RESOURCE_NAMES
    mac_resources = relative_files(mac_root / "Resources")
    if ios_resources != mac_resources:
        only_ios = sorted(ios_resources - mac_resources)
        only_mac = sorted(mac_resources - ios_resources)
        if only_ios:
            failures.append(f"iOS-only shared resources: {', '.join(only_ios)}")
        if only_mac:
            failures.append(f"macOS-only shared resources: {', '.join(only_mac)}")

    for relative_path in sorted(ios_resources & mac_resources):
        ios_path = ios_root / "Resources" / relative_path
        mac_path = mac_root / "Resources" / relative_path
        if not filecmp.cmp(ios_path, mac_path, shallow=False):
            failures.append(f"Resource file drifted: {relative_path}")

    if failures:
        emit("Safari extension parity check failed:")
        for failure in failures:
            emit(f"  {failure}")
        return 1

    emit("Safari extension parity check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
