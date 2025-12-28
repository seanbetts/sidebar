# Test Coverage Analysis

Current coverage snapshot and gaps for the sideBar backend.

**Date**: 2025-12-28 (Refreshed)
**Test Files**: 46 (backend)
**Test Count**: 191 (latest local run may differ; re-run to confirm)

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
- Tool mapper + basic Claude streaming flow are covered.
- Tool definition contracts are covered.
- R2 storage + file tree + files workspace behaviors are covered.
- Chat router has baseline coverage.

### Current Gaps
- Router-level integration coverage remains minimal (beyond basic validation).
- Some storage integration paths are untested.

### ✅ Storage + Workspace (PARTIAL)

| Component | Test File | Status |
|-----------|-----------|--------|
| R2 storage backend | `tests/api/test_r2_storage.py` | ✅ |
| Storage backend factory | `tests/api/test_storage_service.py` | ✅ |
| File tree service | `tests/api/test_file_tree_service.py` | ✅ |
| Files workspace service | `tests/api/test_files_workspace_service.py` | ✅ |
| Notes workspace service | `tests/api/test_notes_workspace_service.py` | ✅ |

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

### ✅ Execution Layer (WELL TESTED)

| Component | Test File | Status | Notes |
|-----------|-----------|--------|-------|
| SkillExecutor | `tests/api/test_skill_executor.py` | ✅ | Async marker added |
| Tool execution handlers | `tests/api/test_execution_handlers.py` | ✅ | Prompt preview + memory tool handlers |
| Tool parameter mapper | `tests/api/test_parameter_mapper.py` | ✅ | CLI argument construction |
| Tool definitions | `tests/api/test_tool_definitions.py` | ✅ | Contract coverage across definitions |

### ✅ Authentication (WELL TESTED)

| Component | Test File | Status | Notes |
|-----------|-----------|--------|-------|
| Auth middleware | `tests/api/test_auth.py` | ✅ | FastMCP lifespan handled |

### ⚠️ MCP Integration (PARTIAL)

| Component | Test File | Status | Notes |
|-----------|-----------|--------|-------|
| MCP client | `tests/test_mcp_client.py` | ✅ | Basic client coverage |
| MCP integration | `tests/test_mcp_integration.py` | ⚠️ | Skips unless `MCP_BASE_URL` set |

### ✅ API Endpoints (PARTIAL)

| Component | Test File | Status |
|-----------|-----------|--------|
| Settings API | `tests/api/test_settings_api.py` | ✅ |
| Chat router | `tests/api/test_chat_router.py` | ✅ |
| Notes router | `tests/api/test_notes_router.py` | ✅ |
| Files router | `tests/api/test_files_router.py` | ✅ |
| Websites router | `tests/api/test_websites_router.py` | ✅ |
| Memories router | `tests/api/test_memories_router.py` | ✅ |
| Conversations router | `tests/api/test_conversations_router.py` | ✅ |
| Places router | `tests/api/test_places_router.py` | ✅ |
| Weather router | `tests/api/test_weather_router.py` | ✅ |
| Scratchpad router | `tests/api/test_scratchpad_router.py` | ✅ |

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

### Storage + Workspace

| Component | Location | Priority | Notes |
|-----------|----------|----------|-------|

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

`conftest.py` mocks critical env vars and skips DB tests when `DATABASE_URL` is not available:

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

### ✅ Pytest Markers

Async marker registered in `backend/pyproject.toml`. Async tests collect and run.

---

## Recommended Test Plan

### Phase 1: Critical Path
1. Add deeper router integration coverage (success paths for more endpoints).

### Phase 2: Storage + Workspace
1. Add tests for R2 storage service.
2. Add tests for `file_tree_service.py` and workspace services.

### Phase 3: Router Integration
1. Add tests for chat + conversation endpoints.
2. Add tests for files/notes/websites/memories CRUD.
3. Add health, places, weather, scratchpad tests.

### Phase 4: Coverage Reporting
Pytest-cov enabled (HTML output to `backend/htmlcov`).

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
