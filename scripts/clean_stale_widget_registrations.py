from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional, Sequence, Tuple


@dataclass(frozen=True)
class WidgetRegistration:
    identifier: str
    path: Path
    uuid: Optional[str] = None
    timestamp: Optional[str] = None
    raw_flags: Tuple[str, ...] = ()


@dataclass(frozen=True)
class ClassificationResult:
    """Partition of widget registrations.

    unknown_non_debug contains records that are preserved without auto-removal,
    even if they exhibit minor debug-like signals outside stale-defined path classes.
    """

    current_workspace: List[WidgetRegistration]
    installed_app: List[WidgetRegistration]
    stale_debug: List[WidgetRegistration]
    unknown_non_debug: List[WidgetRegistration]


_IDENTIFIER_PATTERN = re.compile(r"^[+\-!? ]*\s*(?P<identifier>[^\s(]+)")
_DEBUG_FLAGS = {
    "debug",
    "stale",
    "worktree",
    "temp",
}
_XCODE_BUILD_SETTINGS_PATTERN = re.compile(r"^\s*BUILT_PRODUCTS_DIR\s*=\s*(?P<path>.+?)\s*$")
_XCODE_PROJECT_RELATIVE_PATH = Path("ios/sideBar/sideBar.xcodeproj")
_XCODE_SCHEME = "sideBar"
_XCODE_CONFIGURATION = "Debug"
_XCODE_DESTINATION = "platform=macOS"


def parse_pluginkit_output(lines: Iterable[str]) -> List[WidgetRegistration]:
    registrations: List[WidgetRegistration] = []
    current_block: List[str] = []

    for raw_line in lines:
        line = raw_line.rstrip("\n")
        if not line.strip():
            if current_block:
                block_record = _parse_registration_block(current_block)
                if block_record:
                    registrations.append(block_record)
                current_block = []
            continue

        if "\t" in line:
            tab_record = _parse_tab_line(line)
            if tab_record:
                registrations.append(tab_record)
            continue

        current_block.append(line)

    if current_block:
        block_record = _parse_registration_block(current_block)
        if block_record:
            registrations.append(block_record)

    return registrations


def classify_registrations(
    records: Iterable[WidgetRegistration], current_workspace: Path
) -> ClassificationResult:
    current_paths = _current_registration_roots(current_workspace)
    current_workspace_bucket: List[WidgetRegistration] = []
    installed_app_bucket: List[WidgetRegistration] = []
    stale_debug_bucket: List[WidgetRegistration] = []
    unknown_bucket: List[WidgetRegistration] = []

    for record in records:
        if _is_under_current_paths(record.path, current_paths):
            current_workspace_bucket.append(record)
            continue

        if _is_installed_app(record.path):
            installed_app_bucket.append(record)
            continue

        if _is_stale_debug_registration(record, current_paths):
            stale_debug_bucket.append(record)
            continue

        unknown_bucket.append(record)

    return ClassificationResult(
        current_workspace=current_workspace_bucket,
        installed_app=installed_app_bucket,
        stale_debug=stale_debug_bucket,
        unknown_non_debug=unknown_bucket,
    )


def should_keep_registration(record: WidgetRegistration, current_workspace: Path) -> bool:
    current_paths = _current_registration_roots(current_workspace)
    if _is_under_current_paths(record.path, current_paths):
        return True
    if _is_installed_app(record.path):
        return True
    if _is_stale_debug_registration(record, current_paths):
        return False
    return True


def _parse_registration_block(block: List[str]) -> Optional[WidgetRegistration]:
    if not block:
        return None

    header = block[0].strip()
    if not header:
        return None

    identifier = _extract_identifier(header)
    if not identifier:
        return None

    path_value = _extract_path(block[1:])
    if not path_value:
        return None

    flags = _extract_flags(block[1:])
    return WidgetRegistration(
        identifier=identifier,
        path=Path(path_value),
        raw_flags=flags,
    )


def _parse_tab_line(line: str) -> Optional[WidgetRegistration]:
    parts = line.split("\t")
    if len(parts) < 4:
        return None

    identifier = _extract_identifier(parts[0].strip())
    if not identifier:
        return None

    uuid = parts[1].strip()
    timestamp = parts[2].strip()
    path_value = parts[3].strip()

    if not path_value:
        return None

    return WidgetRegistration(
        identifier=identifier,
        uuid=uuid or None,
        timestamp=timestamp or None,
        path=Path(path_value),
    )


def _extract_identifier(header: str) -> str:
    match = _IDENTIFIER_PATTERN.match(header)
    if match:
        return match.group("identifier")
    return header.split()[0] if header.split() else ""


def _extract_path(lines: List[str]) -> str:
    for line in lines:
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        if key.strip() == "Path":
            return value.strip()
    return ""


def _extract_flags(lines: List[str]) -> Tuple[str, ...]:
    for line in lines:
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        if key.strip() == "Flags":
            fragments = re.split(r"[,\s]+", value.strip())
            return tuple(fragment for fragment in fragments if fragment)
    return tuple()


def _is_under_workspace(path: Path, workspace: Path) -> bool:
    path_str = str(path)
    workspace_str = str(workspace)
    return path_str == workspace_str or path_str.startswith(f"{workspace_str}/")


def _is_under_current_paths(path: Path, current_paths: Sequence[Path]) -> bool:
    return any(_is_under_workspace(path, current_path) for current_path in current_paths)


def _is_installed_app(path: Path) -> bool:
    return str(path).startswith("/Applications/sideBar AI.app")


def _is_stale_path(path: Path, current_paths: Sequence[Path]) -> bool:
    path_str = str(path)
    if path_str.startswith("/private/tmp"):
        return True
    if path_str.startswith("/private/var/folders/") and "/T/" in path_str:
        return True
    if ".git/worktrees" in path_str:
        return True
    if "/DerivedData/" in path_str and not _is_under_current_paths(path, current_paths):
        return True
    return False


def _is_stale_debug_registration(
    record: WidgetRegistration, current_paths: Sequence[Path]
) -> bool:
    return _is_debug_registration(record) and _is_stale_path(record.path, current_paths)


def _is_debug_registration(record: WidgetRegistration) -> bool:
    if record.raw_flags and set(record.raw_flags) & _DEBUG_FLAGS:
        return True
    return _has_debug_path_marker(record.path)


def _has_debug_path_marker(path: Path) -> bool:
    path_str = str(path)
    if "/Build/Products/Debug/" in path_str:
        return True
    if "/DerivedData/" in path_str and "Debug" in path_str:
        return True
    return False


def _list_widget_registrations() -> List[str]:
    result = subprocess.run(
        ["pluginkit", "-m", "-A", "-D", "-v"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.splitlines()


def _remove_widget_registration(path: Path) -> None:
    subprocess.run(["pluginkit", "-r", str(path)], check=True)


def _print_summary(title: str, classification: ClassificationResult) -> None:
    print(title)
    print(f"  current workspace: {len(classification.current_workspace)}")
    print(f"  installed app: {len(classification.installed_app)}")
    print(f"  stale debug: {len(classification.stale_debug)}")
    print(f"  unknown registrations: {len(classification.unknown_non_debug)}")


def _record_matches_bundle_id(record: WidgetRegistration, bundle_id: str) -> bool:
    identifier_base = record.identifier.split("(")[0].strip()
    return identifier_base == bundle_id


def _filter_records_for_bundle(
    records: Iterable[WidgetRegistration], bundle_id: str
) -> List[WidgetRegistration]:
    return [record for record in records if _record_matches_bundle_id(record, bundle_id)]


def _has_workspace_registration_for_bundle(
    classification: ClassificationResult, bundle_id: str
) -> bool:
    return any(
        _record_matches_bundle_id(record, bundle_id)
        for record in classification.current_workspace
    )


def _load_bundle_classification(
    workspace_root: Path, bundle_id: str
) -> ClassificationResult:
    lines = _list_widget_registrations()
    records = parse_pluginkit_output(lines)
    bundle_records = _filter_records_for_bundle(records, bundle_id)
    return classify_registrations(bundle_records, current_workspace=workspace_root)


def _current_registration_roots(workspace_root: Path) -> Tuple[Path, ...]:
    workspace_path = Path(workspace_root)
    active_built_products_dir = _resolve_active_xcode_built_products_dir(workspace_path)
    if active_built_products_dir is None:
        return (workspace_path,)
    return (workspace_path, active_built_products_dir)


def _resolve_active_xcode_built_products_dir(workspace_root: Path) -> Optional[Path]:
    project_path = workspace_root / _XCODE_PROJECT_RELATIVE_PATH
    if not project_path.exists():
        return None

    try:
        result = subprocess.run(
            [
                "xcodebuild",
                "-project",
                str(project_path),
                "-scheme",
                _XCODE_SCHEME,
                "-configuration",
                _XCODE_CONFIGURATION,
                "-destination",
                _XCODE_DESTINATION,
                "-showBuildSettings",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        return None

    for line in result.stdout.splitlines():
        match = _XCODE_BUILD_SETTINGS_PATTERN.match(line)
        if match:
            return Path(match.group("path").strip())
    return None


def run_cleaner(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Clean stale widget registrations reported by pluginkit."
    )
    parser.add_argument(
        "--workspace-root",
        type=Path,
        default=Path.cwd(),
        help="Current workspace root containing the widget build.",
    )
    parser.add_argument(
        "--bundle-id",
        required=True,
        help="Bundle identifier of the widget extension that should remain registered.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be removed without mutating registrations.",
    )
    parser.add_argument(
        "--allow-missing-workspace-registration",
        action="store_true",
        help=(
            "Continue cleanup even when the current workspace build is not yet "
            "registered. Intended for pre-build CI verification flows."
        ),
    )
    args = parser.parse_args(argv)

    workspace_root = args.workspace_root
    bundle_id = args.bundle_id
    try:
        classification = _load_bundle_classification(workspace_root, bundle_id)
    except subprocess.CalledProcessError as exc:
        stderr_output = exc.stderr.strip() if exc.stderr else "pluginkit command failed"
        print(
            "pluginkit failed to list widget registrations "
            f"(exit {exc.returncode}): {stderr_output}"
        )
        print("Skipping cleanup since widget registration enumeration failed.")
        return 0

    _print_summary("Registration summary before cleanup", classification)

    if not _has_workspace_registration_for_bundle(classification, bundle_id):
        if args.allow_missing_workspace_registration:
            print(
                f"Missing current workspace registration for widget bundle {bundle_id}, "
                "continuing because --allow-missing-workspace-registration was set."
            )
        else:
            print(
                f"Missing current workspace registration for widget bundle {bundle_id}. "
                "Cleanup requires an active workspace registration."
            )
            return 1

    cleanup_attempted = False
    removal_failed = False

    if classification.stale_debug:
        if args.dry_run:
            print("Dry run: stale debug registrations flagged for removal:")
        else:
            print("Removing stale debug registrations:")

        for record in classification.stale_debug:
            if args.dry_run:
                print(f"  pluginkit -r {record.path}")
            else:
                cleanup_attempted = True
                try:
                    _remove_widget_registration(record.path)
                    print(f"  Removed {record.path}")
                except subprocess.CalledProcessError as exc:
                    removal_failed = True
                    stderr_output = (
                        exc.stderr.strip()
                        if exc.stderr
                        else exc.stdout.strip()
                        if exc.stdout
                        else "pluginkit command failed"
                    )
                    print(
                        f"  Failed to remove {record.path}, "
                        "treating this as unresolved conflicting state."
                    )
                    print(f"    pluginkit exit {exc.returncode}: {stderr_output}")
    else:
        print("No stale debug registrations detected.")

    try:
        after_summary = _load_bundle_classification(workspace_root, bundle_id)
    except subprocess.CalledProcessError as exc:
        stderr_output = exc.stderr.strip() if exc.stderr else "pluginkit command failed"
        if cleanup_attempted or removal_failed:
            print(
                "Unable to verify registrations after cleanup attempt, "
                "treating this as unresolved conflicting state."
            )
            print(f"  pluginkit exit {exc.returncode}: {stderr_output}")
            return 1
        print(
            "Unable to verify registrations after cleanup attempt. "
            "Skipping post-cleanup verification."
        )
        print(f"  pluginkit exit {exc.returncode}: {stderr_output}")
        return 0
    _print_summary("Registration summary after cleanup", after_summary)

    if not args.dry_run and after_summary.stale_debug:
        print("Conflicting stale debug registrations remain after attempted cleanup:")
        for record in after_summary.stale_debug:
            print(f"  - {record.path} ({record.identifier})")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(run_cleaner())
