#!/usr/bin/env python3
"""Enforce iOS MVVM/store/service architecture boundaries."""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

LAYER_PATHS = {
    "Views": Path("ios/sideBar/sideBar/Views"),
    "ViewModels": Path("ios/sideBar/sideBar/ViewModels"),
    "Stores": Path("ios/sideBar/sideBar/Stores"),
    "Services": Path("ios/sideBar/sideBar/Services"),
}

FORBIDDEN_DEPENDENCIES: dict[str, set[str]] = {
    "Services": {"Stores", "ViewModels", "Views"},
    "Stores": {"ViewModels", "Views"},
    "ViewModels": {"Views"},
}

TYPE_DECL_RE = re.compile(
    r"\b(?:public|internal|private|fileprivate|open)?\s*"
    r"(?:final\s+)?(?:class|struct|enum|protocol|actor|typealias)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)\b"
)
TYPE_REF_RE = re.compile(r"\b[A-Z][A-Za-z0-9_]*\b")


@dataclass(frozen=True)
class TokenUse:
    """One type-like token use in a source file."""

    token: str
    line: int


@dataclass(frozen=True)
class Violation:
    """A prohibited cross-layer dependency."""

    file_path: Path
    line: int
    token: str
    source_layer: str
    forbidden_layers: tuple[str, ...]

    def key(self, repo_root: Path) -> tuple[str, str, str, tuple[str, ...]]:
        """Return stable key used for baseline matching."""
        relative_path = str(self.file_path.relative_to(repo_root))
        return (relative_path, self.source_layer, self.token, self.forbidden_layers)


def iter_layer_files(repo_root: Path) -> list[tuple[Path, str]]:
    """Return all Swift files in configured architecture layers."""
    items: list[tuple[Path, str]] = []
    for layer, relative_root in LAYER_PATHS.items():
        layer_root = repo_root / relative_root
        if not layer_root.exists():
            continue
        for file_path in sorted(layer_root.rglob("*.swift")):
            if file_path.is_file():
                items.append((file_path, layer))
    return items


def strip_comments_and_strings(source: str) -> str:
    """Remove comments/string content while preserving line count and positions."""
    chars = list(source)
    length = len(chars)

    in_line_comment = False
    block_depth = 0
    in_string = False
    in_multiline_string = False
    escaped = False

    i = 0
    while i < length:
        ch = chars[i]
        nxt = chars[i + 1] if i + 1 < length else ""

        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
            else:
                chars[i] = " "
            i += 1
            continue

        if block_depth > 0:
            if ch == "/" and nxt == "*":
                chars[i] = " "
                chars[i + 1] = " "
                block_depth += 1
                i += 2
                continue
            if ch == "*" and nxt == "/":
                chars[i] = " "
                chars[i + 1] = " "
                block_depth -= 1
                i += 2
                continue
            if ch != "\n":
                chars[i] = " "
            i += 1
            continue

        if in_multiline_string:
            if ch == '"' and source[i : i + 3] == '"""':
                chars[i] = " "
                if i + 1 < length:
                    chars[i + 1] = " "
                if i + 2 < length:
                    chars[i + 2] = " "
                in_multiline_string = False
                i += 3
                continue
            if ch != "\n":
                chars[i] = " "
            i += 1
            continue

        if in_string:
            if escaped:
                if ch != "\n":
                    chars[i] = " "
                escaped = False
                i += 1
                continue
            if ch == "\\":
                chars[i] = " "
                escaped = True
                i += 1
                continue
            if ch == '"':
                chars[i] = " "
                in_string = False
                i += 1
                continue
            if ch != "\n":
                chars[i] = " "
            i += 1
            continue

        if ch == "/" and nxt == "/":
            chars[i] = " "
            chars[i + 1] = " "
            in_line_comment = True
            i += 2
            continue

        if ch == "/" and nxt == "*":
            chars[i] = " "
            chars[i + 1] = " "
            block_depth = 1
            i += 2
            continue

        if ch == '"' and source[i : i + 3] == '"""':
            chars[i] = " "
            if i + 1 < length:
                chars[i + 1] = " "
            if i + 2 < length:
                chars[i + 2] = " "
            in_multiline_string = True
            i += 3
            continue

        if ch == '"':
            chars[i] = " "
            in_string = True
            i += 1
            continue

        i += 1

    return "".join(chars)


def collect_declarations(source: str) -> set[str]:
    """Return declared type names in a source file."""
    declared: set[str] = set()
    for line in source.splitlines():
        for match in TYPE_DECL_RE.finditer(line):
            declared.add(match.group(1))
    return declared


def collect_token_uses(source: str) -> list[TokenUse]:
    """Return all type-like token uses from comment/string-stripped source."""
    uses: list[TokenUse] = []
    for line_number, line in enumerate(source.splitlines(), start=1):
        for match in TYPE_REF_RE.finditer(line):
            uses.append(TokenUse(token=match.group(0), line=line_number))
    return uses


def check_boundaries(repo_root: Path) -> list[Violation]:
    """Detect forbidden cross-layer type dependencies."""
    layer_files = iter_layer_files(repo_root)

    type_layers: dict[str, set[str]] = defaultdict(set)
    parsed_sources: dict[Path, str] = {}

    for file_path, layer in layer_files:
        source = file_path.read_text(encoding="utf-8")
        stripped = strip_comments_and_strings(source)
        parsed_sources[file_path] = stripped
        for declared in collect_declarations(stripped):
            type_layers[declared].add(layer)

    violations: list[Violation] = []

    for file_path, layer in layer_files:
        forbidden_layers = FORBIDDEN_DEPENDENCIES.get(layer)
        if not forbidden_layers:
            continue

        seen_tokens: set[str] = set()
        for token_use in collect_token_uses(parsed_sources[file_path]):
            token = token_use.token
            if token in seen_tokens:
                continue

            declared_layers = type_layers.get(token)
            if not declared_layers:
                continue
            if layer in declared_layers:
                continue

            blocked = tuple(sorted(declared_layers.intersection(forbidden_layers)))
            if not blocked:
                continue

            seen_tokens.add(token)
            violations.append(
                Violation(
                    file_path=file_path,
                    line=token_use.line,
                    token=token,
                    source_layer=layer,
                    forbidden_layers=blocked,
                )
            )

    return sorted(
        violations,
        key=lambda item: (str(item.file_path), item.line, item.token),
    )


def load_baseline(
    repo_root: Path,
    baseline_path: Path,
) -> set[tuple[str, str, str, tuple[str, ...]]]:
    """Load allowed legacy violations from JSON baseline."""
    if not baseline_path.exists():
        return set()

    raw = json.loads(baseline_path.read_text(encoding="utf-8"))
    entries = raw.get("allowed_violations", [])
    if not isinstance(entries, list):
        raise ValueError("Baseline must contain an 'allowed_violations' list")

    baseline: set[tuple[str, str, str, tuple[str, ...]]] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        file_path = entry.get("file")
        source_layer = entry.get("source_layer")
        token = entry.get("token")
        forbidden_layers = entry.get("forbidden_layers", [])
        if not isinstance(forbidden_layers, list):
            continue
        if not isinstance(file_path, str):
            continue
        if not isinstance(source_layer, str):
            continue
        if not isinstance(token, str):
            continue
        normalized_path = str((repo_root / file_path).resolve().relative_to(repo_root))
        baseline.add(
            (
                normalized_path,
                source_layer,
                token,
                tuple(sorted(str(layer) for layer in forbidden_layers)),
            )
        )
    return baseline


def emit(message: str = "") -> None:
    """Write one line to stdout."""
    sys.stdout.write(f"{message}\n")


def main() -> int:
    """Run architecture boundary checks and return process exit code."""
    parser = argparse.ArgumentParser(
        description="Check iOS architecture boundaries for MVVM/store/service layers."
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Repository root path",
    )
    parser.add_argument(
        "--baseline",
        type=Path,
        default=Path("scripts/ios_architecture_boundaries_baseline.json"),
        help="Path to allowed-violations baseline JSON",
    )
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    baseline_path = (repo_root / args.baseline).resolve()

    violations = check_boundaries(repo_root)
    baseline = load_baseline(repo_root, baseline_path)

    current_keys = {violation.key(repo_root) for violation in violations}
    failing = [
        violation
        for violation in violations
        if violation.key(repo_root) not in baseline
    ]
    stale = sorted(baseline.difference(current_keys))

    if failing:
        emit("iOS architecture boundary violations found:")
        for violation in failing:
            relative_path = violation.file_path.relative_to(repo_root)
            blocked = ", ".join(violation.forbidden_layers)
            emit(
                f"  {relative_path}:{violation.line}: "
                f"{violation.source_layer} references {violation.token} "
                f"from forbidden layer(s): {blocked}"
            )
        return 1

    if stale:
        emit("iOS architecture boundary baseline has stale entries:")
        for relative_path, source_layer, token, forbidden_layers in stale:
            blocked = ", ".join(forbidden_layers)
            emit(
                f"  {relative_path}: "
                f"{source_layer} -> {token} ({blocked}) no longer present"
            )
        emit("Update scripts/ios_architecture_boundaries_baseline.json.")
        return 1

    emit(
        "iOS architecture boundary check passed "
        "(Services->Stores/ViewModels/Views, "
        "Stores->ViewModels/Views, ViewModels->Views)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
