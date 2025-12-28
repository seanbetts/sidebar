# Test Coverage Analysis

Current coverage snapshot and gaps for the sideBar backend.

**Date**: 2025-12-28 (Updated)
**Test Files**: 13
**Test Functions**: 23 (plus parametrized cases)

---

## Executive Summary

### Recent Refactor Impact
- Tool orchestration split into `services/tools/*` (definitions, parameter mapping, execution handlers).
- Streaming logic moved into `claude_streaming.py`.
- Memory tool split into `services/memory_tools/*`.
- Workspace routing moved into `*_workspace_service.py`.
- Storage now uses R2-backed services; tmpfs used for scratch.

### Current Strengths
- Prompt construction and context assembly are covered.
- Core Notes/Websites service logic is covered.
- Security primitives (path validation, audit logging) are covered.

### Current Gaps
- No tests for Claude streaming + tool execution flow.
- Tool definitions and parameter mapping are untested.
- Router-level integration coverage remains minimal.
- R2 storage integration and file tree services are untested.

---

## Current Coverage

### ✅ Prompts & Context (WELL TESTED)

| Component | Test File | Status |
|-----------|-----------|--------|
| Prompt templates | `tests/api/test_prompts.py` | ✅ |
| Prompt context service | `tests/api/test_prompt_context_service.py` | ✅ |

### ✅ API Services (WELL TESTED)

| Component | Test File | Status |
|-----------|-----------|--------|
| NotesService | `tests/api/test_notes_service.py` | ✅ |
| WebsitesService | `tests/api/test_websites_service.py` | ✅ |

### ✅ Security Layer (WELL TESTED)

| Component | Test File | Status |
|-----------|-----------|--------|
| PathValidator | `tests/api/test_path_validator.py` | ✅ |
| AuditLogger | `tests/api/test_audit_logger.py` | ✅ |

### ⚠️ Execution Layer (PARTIAL)

| Component | Test File | Status | Notes |
|-----------|-----------|--------|-------|
| SkillExecutor | `tests/api/test_skill_executor.py` | ⚠️ | Requires asyncio marker |

### ⚠️ Authentication (PARTIAL)

| Component | Test File | Status | Notes |
|-----------|-----------|--------|-------|
| Auth middleware | `tests/api/test_auth.py` | ⚠️ | Requires asyncio marker |

### ⚠️ MCP Integration (PARTIAL)

| Component | Test File | Status | Notes |
|-----------|-----------|--------|-------|
| MCP client | `tests/test_mcp_client.py` | ✅ | Basic client coverage |
| MCP integration | `tests/test_mcp_integration.py` | ⚠️ | Requires asyncio marker |

### ✅ API Endpoints (PARTIAL)

| Component | Test File | Status |
|-----------|-----------|--------|
| Settings API | `tests/api/test_settings_api.py` | ✅ |

### ✅ Utility Scripts (PARTIAL)

| Script | Test File | Status |
|--------|-----------|--------|
| add_skill_dependencies | `tests/scripts/test_add_skill_dependencies.py` | ✅ |
| skill-creator validate | `tests/skills/skill_creator/test_quick_validate.py` | ✅ |

---

## Missing Coverage (High Priority)

### Critical Path

| Component | Location | Priority | Notes |
|-----------|----------|----------|-------|
| Claude streaming | `api/services/claude_streaming.py` | 🔴 HIGH | Token stream, tool loop, error paths |
| Tool mapping | `api/services/tool_mapper.py` | 🔴 HIGH | Routing + allowed skills |
| Tool execution handlers | `api/services/tools/execution_handlers.py` | 🔴 HIGH | Shared tool execution flow |
| Tool parameter mapping | `api/services/tools/parameter_mapper.py` | 🔴 HIGH | Argument construction |
| Tool definitions | `api/services/tools/definitions_*.py` | 🔴 HIGH | Contract correctness |

### Storage + Workspace

| Component | Location | Priority | Notes |
|-----------|----------|----------|-------|
| R2 storage backend | `api/services/storage/` | 🔴 HIGH | Upload/download paths |
| File tree service | `api/services/file_tree_service.py` | 🟡 MEDIUM | Listing + filters |
| Files workspace service | `api/services/files_workspace_service.py` | 🟡 MEDIUM | CRUD + indexing |
| Notes workspace service | `api/services/notes_workspace_service.py` | 🟡 MEDIUM | Tree/rename/update |

### Memory Tool

| Component | Location | Priority | Notes |
|-----------|----------|----------|-------|
| Memory operations | `api/services/memory_tools/*` | 🟡 MEDIUM | View/create/insert/rename/delete |

### Routers (Integration)

| Router | Location | Priority |
|--------|----------|----------|
| Chat | `api/routers/chat.py` | 🔴 HIGH |
| Conversations | `api/routers/conversations.py` | 🔴 HIGH |
| Files | `api/routers/files.py` | 🟡 MEDIUM |
| Notes | `api/routers/notes.py` | 🟡 MEDIUM |
| Websites | `api/routers/websites.py` | 🟡 MEDIUM |
| Memories | `api/routers/memories.py` | 🟡 MEDIUM |
| Skills | `api/routers/skills.py` | 🟢 LOW |
| Places | `api/routers/places.py` | 🟢 LOW |
| Weather | `api/routers/weather.py` | 🟢 LOW |
| Scratchpad | `api/routers/scratchpad.py` | 🟢 LOW |

---

## Test Infrastructure Status

### ✅ Environment Mocking

`conftest.py` mocks critical env vars; update values to align with Supabase/R2:

```python
os.environ.setdefault("BEARER_TOKEN", "test-bearer-token-12345")
os.environ.setdefault("ANTHROPIC_API_KEY", "test-anthropic-key-12345")
os.environ.setdefault("DATABASE_URL", "postgresql://.../sidebar_test")
os.environ.setdefault("SUPABASE_PROJECT_ID", "test_project")
os.environ.setdefault("R2_ENDPOINT", "https://test.r2.cloudflarestorage.com")
os.environ.setdefault("R2_BUCKET", "sidebar")
os.environ.setdefault("R2_ACCESS_KEY_ID", "test_access_key")
os.environ.setdefault("R2_SECRET_ACCESS_KEY", "test_secret_key")
```

### ⚠️ Pytest Markers

Async tests still fail to collect because `asyncio` is not registered.

Add in `backend/pyproject.toml`:

```toml
[tool.pytest.ini_options]
markers = [
    "slow: marks tests as slow (deselect with '-m \"not slow\"')",
    "integration: marks tests as integration tests",
    "asyncio: marks tests as async tests",
]
```

Affected tests:
- `tests/api/test_auth.py`
- `tests/api/test_skill_executor.py`
- `tests/test_mcp_integration.py`

---

## Recommended Test Plan

### Phase 1: Critical Path
1. Add `asyncio` marker and ensure all tests collect.
2. Add unit tests for `tool_mapper.py`, `execution_handlers.py`, and `parameter_mapper.py`.
3. Add streaming tests for `claude_streaming.py` using mocked tool results.

### Phase 2: Storage + Workspace
1. Add tests for R2 storage service.
2. Add tests for `file_tree_service.py` and workspace services.

### Phase 3: Router Integration
1. Add tests for chat + conversation endpoints.
2. Add tests for files/notes/websites/memories CRUD.
3. Add health, places, weather, scratchpad tests.

### Phase 4: Coverage Reporting
Enable pytest-cov once baseline coverage improves:

```toml
addopts = [
    "-v",
    "--strict-markers",
    "--tb=short",
    "--cov=api",
    "--cov-report=term-missing",
    "--cov-report=html",
    "--cov-fail-under=80",
]
```
