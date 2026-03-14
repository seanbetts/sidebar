from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional, Tuple


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
    workspace_path = Path(current_workspace)
    current_workspace_bucket: List[WidgetRegistration] = []
    installed_app_bucket: List[WidgetRegistration] = []
    stale_debug_bucket: List[WidgetRegistration] = []
    unknown_bucket: List[WidgetRegistration] = []

    for record in records:
        if _is_under_workspace(record.path, workspace_path):
            current_workspace_bucket.append(record)
            continue

        if _is_installed_app(record.path):
            installed_app_bucket.append(record)
            continue

        if _is_stale_debug_registration(record, workspace_path):
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
    workspace_path = Path(current_workspace)
    if _is_under_workspace(record.path, workspace_path):
        return True
    if _is_installed_app(record.path):
        return True
    if _is_stale_debug_registration(record, workspace_path):
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


def _is_installed_app(path: Path) -> bool:
    return str(path).startswith("/Applications/sideBar AI.app")


def _is_stale_path(path: Path, workspace: Path) -> bool:
    path_str = str(path)
    if path_str.startswith("/private/tmp"):
        return True
    if ".git/worktrees" in path_str:
        return True
    if "/DerivedData/" in path_str and not _is_under_workspace(path, workspace):
        return True
    return False


def _is_stale_debug_registration(record: WidgetRegistration, workspace: Path) -> bool:
    return _is_debug_registration(record) and _is_stale_path(record.path, workspace)


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


def _remove_widget_registration(uuid: str) -> None:
    subprocess.run(["pluginkit", "-r", uuid], check=True)


def _print_summary(title: str, classification: ClassificationResult) -> None:
    print(title)
    print(f"  current workspace: {len(classification.current_workspace)}")
    print(f"  installed app: {len(classification.installed_app)}")
    print(f"  stale debug: {len(classification.stale_debug)}")
    print(f"  unknown registrations: {len(classification.unknown_non_debug)}")


def _record_matches_bundle_id(record: WidgetRegistration, bundle_id: str) -> bool:
    identifier_base = record.identifier.split("(")[0].strip()
    return identifier_base == bundle_id


def _has_workspace_registration_for_bundle(
    classification: ClassificationResult, bundle_id: str
) -> bool:
    return any(
        _record_matches_bundle_id(record, bundle_id)
        for record in classification.current_workspace
    )


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
    args = parser.parse_args(argv)

    workspace_root = args.workspace_root
    bundle_id = args.bundle_id
    try:
        lines = _list_widget_registrations()
    except subprocess.CalledProcessError as exc:
        stderr_output = exc.stderr.strip() if exc.stderr else "pluginkit command failed"
        print(
            f"pluginkit failed to list widget registrations "
            f"(exit {exc.returncode}): {stderr_output}"
        )
        return exc.returncode or 1
    records = parse_pluginkit_output(lines)
    classification = classify_registrations(records, current_workspace=workspace_root)

    _print_summary("Registration summary before cleanup", classification)

    if not _has_workspace_registration_for_bundle(classification, bundle_id):
        print(
            f"Missing current workspace registration for widget bundle {bundle_id}. "
            "Cleanup requires an active workspace registration."
        )
        return 1

    conflicts = [record for record in classification.stale_debug if not record.uuid]
    if conflicts:
        print("Conflicting stale debug registrations remain:")
        for record in conflicts:
            print(f"  - {record.path} ({record.identifier})")
        return 1

    if classification.stale_debug:
        if args.dry_run:
            print("Dry run: stale debug registrations flagged for removal:")
        else:
            print("Removing stale debug registrations:")

        for record in classification.stale_debug:
            if record.uuid is None:
                continue
            if args.dry_run:
                print(f"  pluginkit -r {record.uuid} ({record.path})")
            else:
                _remove_widget_registration(record.uuid)
                print(f"  Removed {record.path}")
    else:
        print("No stale debug registrations detected.")

    after_summary = ClassificationResult(
        current_workspace=classification.current_workspace,
        installed_app=classification.installed_app,
        stale_debug=[],
        unknown_non_debug=classification.unknown_non_debug,
    )
    _print_summary("Registration summary after cleanup", after_summary)
    return 0


if __name__ == "__main__":
    sys.exit(run_cleaner())
