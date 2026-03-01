import ast
import re
from pathlib import Path


BACKEND_ROOT = Path(__file__).resolve().parents[2]
API_ROOT = BACKEND_ROOT / "api"
NOTES_SKILLS_ROOT = BACKEND_ROOT / "skills" / "notes" / "scripts"
ALLOWED_CONTENT_ASSIGNMENT_FILES = {
    API_ROOT / "services" / "notes_service.py",
}
NOTE_CONTENT_ASSIGNMENT_PATTERN = re.compile(r"\b[a-zA-Z_][a-zA-Z0-9_]*\.content\s*=")
NOTES_CONTENT_ASSIGNMENT_SCAN_FILES = (
    API_ROOT / "services" / "notes_helpers.py",
    API_ROOT / "services" / "notes_payloads.py",
    API_ROOT / "services" / "notes_service.py",
    API_ROOT / "services" / "notes_sync_service.py",
    API_ROOT / "services" / "notes_workspace_service.py",
    API_ROOT / "services" / "notes_write_contract.py",
    API_ROOT / "services" / "test_data_service.py",
    API_ROOT / "routers" / "notes.py",
    API_ROOT / "routers" / "scratchpad.py",
)


def _iter_contract_files() -> list[Path]:
    files = [path for path in API_ROOT.rglob("*.py") if path.is_file()]
    files.extend(path for path in NOTES_SKILLS_ROOT.rglob("*.py") if path.is_file())
    return sorted(set(files))


def test_notes_service_writes_require_plain_text_keyword() -> None:
    violations: list[str] = []
    for path in _iter_contract_files():
        source = path.read_text(encoding="utf-8")
        tree = ast.parse(source, filename=str(path))
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            func = node.func
            if not isinstance(func, ast.Attribute):
                continue
            if not isinstance(func.value, ast.Name) or func.value.id != "NotesService":
                continue
            if func.attr not in {"create_note", "update_note"}:
                continue
            has_plain_text_kwarg = any(
                keyword.arg == "plain_text" for keyword in node.keywords
            )
            if has_plain_text_kwarg:
                continue
            relative = path.relative_to(BACKEND_ROOT)
            violations.append(f"{relative}:{node.lineno}")
    assert not violations, (
        "NotesService write call sites missing plain_text keyword:\n"
        + "\n".join(violations)
    )


def test_note_content_assignment_only_happens_in_notes_service() -> None:
    violations: list[str] = []
    for path in [*NOTES_CONTENT_ASSIGNMENT_SCAN_FILES, *NOTES_SKILLS_ROOT.rglob("*.py")]:
        if not path.exists() or not path.is_file():
            continue
        if path in ALLOWED_CONTENT_ASSIGNMENT_FILES:
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        for line_number, line in enumerate(lines, start=1):
            if line.strip().startswith("#"):
                continue
            if NOTE_CONTENT_ASSIGNMENT_PATTERN.search(line):
                relative = path.relative_to(BACKEND_ROOT)
                violations.append(f"{relative}:{line_number}")
    assert not violations, (
        "Direct .content assignment is restricted to notes_service.py:\n"
        + "\n".join(violations)
    )
