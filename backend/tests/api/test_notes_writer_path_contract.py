import ast
import re
from pathlib import Path

from api.services.tools.definitions_notes import get_notes_definitions


BACKEND_ROOT = Path(__file__).resolve().parents[2]
API_ROOT = BACKEND_ROOT / "api"
NOTES_SKILLS_ROOT = BACKEND_ROOT / "skills" / "notes" / "scripts"
ALLOWED_CONTENT_ASSIGNMENT_FILES = {
    API_ROOT / "services" / "notes_service.py",
}
NOTE_CONTENT_ASSIGNMENT_PATTERN = re.compile(r"\b[a-zA-Z_][a-zA-Z0-9_]*\.content\s*=")
NOTES_CONTENT_ASSIGNMENT_SCAN_FILES = (
    API_ROOT / "services" / "notes_helpers.py",
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


def test_notes_service_writes_require_document_keyword() -> None:
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
            has_document_kwarg = any(
                keyword.arg == "document" for keyword in node.keywords
            )
            if has_document_kwarg or len(node.args) >= 3:
                continue
            relative = path.relative_to(BACKEND_ROOT)
            violations.append(f"{relative}:{node.lineno}")
    assert not violations, (
        "NotesService write call sites missing document keyword:\n"
        + "\n".join(violations)
    )


def test_note_content_assignment_only_happens_in_notes_service() -> None:
    violations: list[str] = []
    for path in [
        *NOTES_CONTENT_ASSIGNMENT_SCAN_FILES,
        *NOTES_SKILLS_ROOT.rglob("*.py"),
    ]:
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


def test_notes_tool_definitions_use_document_payloads_and_semantic_writer() -> None:
    definitions = get_notes_definitions()

    create = definitions["Create Note"]
    edit_note = definitions["Edit Note"]
    scratchpad_update = definitions["Update Scratchpad"]

    assert create["script"] == "save_note_document.py"
    assert edit_note["script"] == "edit_note.py"
    assert "Update Note" not in definitions
    assert "document" in create["input_schema"]["properties"]
    assert "content" not in create["input_schema"]["properties"]
    assert create["input_schema"]["required"] == ["document"]
    assert "expected_updated_at" in edit_note["input_schema"]["properties"]
    assert "operations" in edit_note["input_schema"]["properties"]
    assert "document" not in edit_note["input_schema"]["properties"]
    assert "content" not in edit_note["input_schema"]["properties"]
    assert "document" in scratchpad_update["input_schema"]["properties"]
    assert "content" not in scratchpad_update["input_schema"]["properties"]
    assert scratchpad_update["input_schema"]["required"] == ["document"]


def test_notes_create_contract_describes_nested_document_shape() -> None:
    definitions = get_notes_definitions()
    create = definitions["Create Note"]
    document_description = create["input_schema"]["properties"]["document"][
        "description"
    ]
    notes_skill = (BACKEND_ROOT / "skills" / "notes" / "SKILL.md").read_text(
        encoding="utf-8"
    )

    assert "children" in document_description
    assert "blockquote" in document_description
    assert "list_item" in document_description
    assert "top-level list_item" in document_description
    assert "children" in notes_skill


def test_notes_skill_includes_canonical_nested_document_example() -> None:
    notes_skill = (BACKEND_ROOT / "skills" / "notes" / "SKILL.md").read_text(
        encoding="utf-8"
    )

    assert "Canonical example:" in notes_skill
    assert '"type": "unordered_list"' in notes_skill
    assert '"type": "blockquote"' in notes_skill
    assert '"children"' in notes_skill
    assert "do not send `blockquote.content`" in notes_skill


def test_tool_mapper_failure_logging_happens_in_executor_only() -> None:
    mapper_source = (
        API_ROOT / "services" / "agent" / "tools" / "mapper.py"
    ).read_text(encoding="utf-8")

    normalize_index = mapper_source.index("normalized = self._normalize_result(result)")
    success_guard_index = mapper_source.index(
        'if normalized.get("success"):',
        normalize_index,
    )
    success_log_index = mapper_source.index(
        "AuditLogger.log_tool_call(",
        success_guard_index,
    )

    assert normalize_index < success_guard_index < success_log_index
    assert (
        "tool_name=display_name,\n"
        "                parameters=log_params,\n"
        "                duration_ms=(time.time() - start_time) * 1000,\n"
        "                success=result.get(\"success\", False),"
    ) not in mapper_source


def test_notes_writer_surface_no_longer_references_save_markdown_or_content_flags() -> None:
    contract_files = (
        API_ROOT / "mcp" / "notes_tools.py",
        API_ROOT / "services" / "tools" / "definitions_notes.py",
        API_ROOT / "services" / "tools" / "parameter_builders" / "notes_builder.py",
        API_ROOT / "services" / "tools" / "parameter_mapper.py",
        API_ROOT
        / "services"
        / "agent"
        / "tools"
        / "parameter_builders"
        / "notes_builder.py",
    )

    offenders: list[str] = []
    for path in contract_files:
        source = path.read_text(encoding="utf-8")
        if "save_markdown.py" in source:
            offenders.append(f"{path.relative_to(BACKEND_ROOT)}:save_markdown.py")
        if "--content" in source:
            offenders.append(f"{path.relative_to(BACKEND_ROOT)}:--content")

    assert offenders == []
