from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
TEST_ROOTS = (
    REPO_ROOT / "backend" / "tests",
    REPO_ROOT / "frontend" / "src" / "tests",
    REPO_ROOT / "website" / "src" / "test",
    REPO_ROOT / "ios" / "sideBar" / "sideBarTests",
    REPO_ROOT / "ios" / "sideBar" / "ShareExtensionTests",
)
TEST_FILE_SUFFIXES = {".py", ".ts", ".tsx", ".swift"}
DEVELOPMENT_TASK_PREFIX = re.compile(r"^(Task|Ticket|Story|Phase)\d+[A-Z_]")
SWIFT_DEVELOPMENT_TASK_IDENTIFIER = re.compile(r"\b(Task|Ticket|Story|Phase)\d+[A-Z]\w*")


def test_test_files_do_not_use_development_task_labels() -> None:
    """Test names should describe behavior instead of the implementation task."""
    violations: list[str] = []

    for test_file in _test_files():
        if DEVELOPMENT_TASK_PREFIX.search(test_file.stem):
            violations.append(f"{test_file.relative_to(REPO_ROOT)} uses a development task label")

        if test_file.suffix == ".swift":
            violations.extend(_swift_identifier_violations(test_file))

    assert not violations, "Rename task-labelled tests:\n" + "\n".join(violations)


def _test_files() -> list[Path]:
    files: list[Path] = []
    for root in TEST_ROOTS:
        if not root.exists():
            continue
        files.extend(path for path in root.rglob("*") if path.suffix in TEST_FILE_SUFFIXES)
    return sorted(files)


def _swift_identifier_violations(test_file: Path) -> list[str]:
    violations: list[str] = []
    for line_number, line in enumerate(test_file.read_text().splitlines(), start=1):
        for match in SWIFT_DEVELOPMENT_TASK_IDENTIFIER.finditer(line):
            violations.append(
                f"{test_file.relative_to(REPO_ROOT)}:{line_number} "
                f"uses development task identifier {match.group(0)!r}"
            )
    return violations
