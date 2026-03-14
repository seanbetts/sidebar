from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional


@dataclass(frozen=True)
class WidgetRegistration:
    identifier: str
    path: Path
    status: Optional[str] = None


@dataclass(frozen=True)
class ClassificationResult:
    current_workspace: List[WidgetRegistration]
    installed_app: List[WidgetRegistration]
    stale_debug: List[WidgetRegistration]
    unknown_non_debug: List[WidgetRegistration]


_IDENTIFIER_PATTERN = re.compile(r"^[+\-!? ]*\s*(?P<identifier>[^\s(]+)")


def parse_pluginkit_output(lines: Iterable[str]) -> List[WidgetRegistration]:
    blocks: List[List[str]] = []
    current_block: List[str] = []

    for raw_line in lines:
        line = raw_line.rstrip("\n")
        if not line.strip():
            if current_block:
                blocks.append(current_block)
                current_block = []
            continue
        current_block.append(line)

    if current_block:
        blocks.append(current_block)

    registrations: List[WidgetRegistration] = []
    for block in blocks:
        registration = _parse_registration_block(block)
        if registration:
            registrations.append(registration)
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

        if _is_stale_debug_path(record.path, workspace_path):
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
    if _is_stale_debug_path(record.path, workspace_path):
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

    status_char = header[0] if header[0] in "+-!? " else None
    return WidgetRegistration(identifier=identifier, path=Path(path_value), status=status_char)


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


def _is_under_workspace(path: Path, workspace: Path) -> bool:
    path_str = str(path)
    workspace_str = str(workspace)
    return path_str == workspace_str or path_str.startswith(f"{workspace_str}/")


def _is_installed_app(path: Path) -> bool:
    return str(path).startswith("/Applications/sideBar AI.app")


def _is_stale_debug_path(path: Path, workspace: Path) -> bool:
    if _is_under_workspace(path, workspace):
        return False

    path_str = str(path)
    if path_str.startswith("/private/tmp"):
        return True
    if ".git/worktrees" in path_str:
        return True
    if "/DerivedData/" in path_str:
        return True
    return False
