# Refactoring Plan - 2026 Q1

**Date:** 2026-01-04
**Status:** In Progress
**Priority:** High - Multiple AGENTS.md constraint violations identified

## Executive Summary

This plan addresses critical technical debt, architecture violations, and code quality issues identified in a comprehensive codebase review. The refactoring focuses on:

1. **Compliance** - Fix 6 files exceeding LOC limits (AGENTS.md constraints)
2. **Architecture** - Move DB queries from routers to services (separation of concerns)
3. **DRY** - Eliminate massive duplication (70 API proxy files, 20+ UUID validators)
4. **Maintainability** - Refactor 692-line parameter mapper into cohesive classes
5. **Quality** - Standardize error handling and improve testability

**Impact:** High-priority items violate core architectural constraints and create maintenance burden.

**Estimated Effort:** 3-4 weeks (staggered phases, TDD approach)

---

## Table of Contents

- [Priority Matrix](#priority-matrix)
- [High Priority Items](#high-priority-items)
- [Medium Priority Items](#medium-priority-items)
- [Low Priority Items](#low-priority-items)
- [Implementation Phases](#implementation-phases)
- [Success Metrics](#success-metrics)
- [Risks & Mitigation](#risks--mitigation)

---

## Priority Matrix

### High Priority (P0) - Start Immediately
1. **Architecture Violations** - DB queries in routers (5 files) ✅
2. **LOC Limit Violations** - 6 files exceed AGENTS.md limits ✅
3. **Frontend API Duplication** - 70 identical proxy files 🔄 (in progress)

### Medium Priority (P1) - After P0 Complete
4. **Parameter Builder Refactor** - 692-line file into classes
5. **UUID Validation Duplication** - 20+ instances
6. **Error Handling Standardization** - 161 console.error statements
7. **JSONB Update Audit** - Ensure flag_modified usage

### Low Priority (P2) - Polish & Debt Reduction
8. **Component Event Handler Extraction** - Testability improvements
9. **Naming Consistency** - Standardize conventions
10. **Helper Function Organization** - Consolidate utilities

---

## High Priority Items

### P0-1: Architecture Violation - DB Queries in Routers ✅

**Problem:** Multiple routers contain direct database queries instead of using the service layer, violating core constraint: "All database access through backend/api/services/"

**Affected Files:**
- `backend/api/routers/ingestion.py` (lines 306-363)
- `backend/api/routers/chat.py`
- `backend/api/routers/memories.py`
- `backend/api/routers/conversations.py`
- `backend/api/routers/websites.py`

**Example Violation** (ingestion.py:306-363):
```python
@router.get("/ingestions", response_model=list[IngestionListItem])
async def list_ingestions(
    user_id: str = Depends(get_user_id),
    db: Session = Depends(get_db),
):
    records = (
        db.query(IngestedFile)
        .filter(
            IngestedFile.user_id == user_id,
            IngestedFile.deleted_at.is_(None),
        )
        .order_by(IngestedFile.created_at.desc())
        .limit(50)
        .all()
    )
    # ... more DB operations
```

**Solution:**
1. Create service methods in appropriate service classes:
   - `FileIngestionService.list_ingestions(db, user_id) -> list[IngestedFile]`
   - `ChatService.list_conversations(db, user_id) -> list[Conversation]`
   - etc.

2. Update routers to call service methods:
```python
@router.get("/ingestions", response_model=list[IngestionListItem])
async def list_ingestions(
    user_id: str = Depends(get_user_id),
    db: Session = Depends(get_db),
):
    records = FileIngestionService.list_ingestions(db, user_id)
    return [
        IngestionListItem(
            file_id=str(r.file_id),
            # ... mapping logic
        )
        for r in records
    ]
```

3. Write tests for new service methods before implementation (TDD)

**Files to Modify:**
- `backend/api/services/file_ingestion_service.py` (add methods)
- `backend/api/routers/ingestion.py` (remove queries, call service)
- `backend/api/services/chat_service.py` (add methods if needed)
- `backend/api/routers/chat.py` (remove queries, call service)
- `backend/api/routers/memories.py` (remove queries, call service)
- `backend/api/routers/conversations.py` (remove queries, call service)
- `backend/api/routers/websites.py` (standardize pattern)

**Tests Required:**
- `backend/tests/test_file_ingestion_service.py` (new service methods)
- `backend/tests/test_chat_service.py` (new service methods)
- Integration tests for affected routes

**Estimated Effort:** 3 days
**Status:** Completed
**Risk:** Medium - Could break existing functionality if not tested thoroughly

---

### P0-2: LOC Limit Violations

**Problem:** 6 files exceed AGENTS.md line-of-code limits, making them harder to maintain and test.

#### Backend Files

##### 2a. `backend/api/routers/ingestion.py` (644 lines, limit: 500) ✅

**Issue:** Helper functions and business logic mixed with route definitions.

**Solution:**
1. Extract helper functions to `backend/api/routers/ingestion_helpers.py`:
   - `_category_for_file()`
   - `_normalize_youtube_url()`
   - `_extract_youtube_id()`
   - `_user_message_for_error()`
   - `_filter_user_derivatives()`
   - `_recommended_viewer()`
   - `_staging_path()`
   - `_safe_cleanup()`
   - `_staging_storage_key()`

2. Keep only route definitions in `ingestion.py`

**Expected Result:** ingestion.py ~400 lines, new helpers file ~150 lines

**Files to Create:**
- `backend/api/routers/ingestion_helpers.py`

**Files to Modify:**
- `backend/api/routers/ingestion.py`

**Tests Required:**
- `backend/tests/test_ingestion_helpers.py` (test extracted functions)
- Verify existing ingestion route tests still pass

**Estimated Effort:** 1 day
**Status:** Completed

---

##### 2b. `backend/api/services/tools/parameter_mapper.py` (692 lines, limit: 600) ✅

**Issue:** 40+ individual parameter builder functions with no logical grouping.

**Solution:** Refactor into cohesive builder classes.

**Current Structure:**
```python
def build_notes_create_args(params: dict) -> list: ...
def build_notes_update_args(params: dict) -> list: ...
def build_notes_delete_args(params: dict) -> list: ...
def build_notes_pin_args(params: dict) -> list: ...
def build_notes_move_args(params: dict) -> list: ...
# ... 35+ more functions
```

**Proposed Structure:**
```python
# backend/api/services/tools/parameter_builders/__init__.py
from .notes_builder import NotesParameterBuilder
from .website_builder import WebsiteParameterBuilder
from .files_builder import FilesParameterBuilder
from .things_builder import ThingsParameterBuilder
# ... etc.

# backend/api/services/tools/parameter_builders/base.py
class BaseParameterBuilder:
    """Base class with common parameter patterns."""

    @staticmethod
    def with_defaults(params: dict, args: list) -> list:
        """Add common flags like --database, --user-id, --json."""
        result = args.copy()
        if "database" in params:
            result.extend(["--database", params["database"]])
        if "user_id" in params:
            result.extend(["--user-id", params["user_id"]])
        result.append("--json")
        return result

# backend/api/services/tools/parameter_builders/notes_builder.py
class NotesParameterBuilder(BaseParameterBuilder):
    """Parameter builders for notes skills."""

    @staticmethod
    def build_create_args(params: dict) -> list:
        args = [
            params["title"],
            "--content", params.get("content", ""),
            "--mode", "create"
        ]
        return BaseParameterBuilder.with_defaults(params, args)

    @staticmethod
    def build_update_args(params: dict) -> list:
        args = [
            "--note-id", params["note_id"],
            "--mode", "update"
        ]
        if "title" in params:
            args.extend(["--title", params["title"]])
        if "content" in params:
            args.extend(["--content", params["content"]])
        return BaseParameterBuilder.with_defaults(params, args)

    # ... other note-related builders

# backend/api/services/tools/parameter_builders/website_builder.py
class WebsiteParameterBuilder(BaseParameterBuilder):
    """Parameter builders for website skills."""

    @staticmethod
    def build_save_args(params: dict) -> list:
        args = [
            params["url"],
            "--mode", "save"
        ]
        if "title" in params:
            args.extend(["--title", params["title"]])
        return BaseParameterBuilder.with_defaults(params, args)

    # ... other website-related builders
```

**Migration Strategy:**
1. Create new directory structure
2. Implement base class with common patterns
3. Migrate builders one domain at a time (notes → websites → files → things)
4. Update imports in parameter_mapper.py to use new classes
5. Delete old functions once all references updated

**Files to Create:**
- `backend/api/services/tools/parameter_builders/__init__.py`
- `backend/api/services/tools/parameter_builders/base.py`
- `backend/api/services/tools/parameter_builders/notes_builder.py`
- `backend/api/services/tools/parameter_builders/website_builder.py`
- `backend/api/services/tools/parameter_builders/files_builder.py`
- `backend/api/services/tools/parameter_builders/things_builder.py`

**Files to Modify:**
- `backend/api/services/tools/parameter_mapper.py` (update imports, delegate to builders)

**Tests Required:**
- `backend/tests/test_parameter_builders.py` (test all builders)
- Verify existing parameter mapper tests still pass

**Estimated Effort:** 2 days
**Status:** Completed

---

##### 2c. `backend/api/services/skill_file_ops_ingestion.py` (638 lines, limit: 600) ✅

**Issue:** Mixed concerns - file operations and search functionality.

**Solution:**
1. Extract search functionality to `backend/api/services/file_search_service.py`:
   - Search-related methods
   - Query building logic
   - Result formatting

2. Keep only file operations in `skill_file_ops_ingestion.py`

**Expected Result:** skill_file_ops_ingestion.py ~450 lines, new search service ~200 lines

**Files to Create:**
- `backend/api/services/file_search_service.py`

**Files to Modify:**
- `backend/api/services/skill_file_ops_ingestion.py`

**Tests Required:**
- `backend/tests/test_file_search_service.py`
- Verify existing file ops tests still pass

**Estimated Effort:** 1 day
**Status:** Completed

---

#### Frontend Files

##### 2d. `frontend/src/lib/components/things/ThingsTasksContent.svelte` (689 lines, limit: 600) ✅

**Issue:** Presentational component mixing UI and business logic.

**Solution:** Split into smaller, focused components.

**Proposed Structure:**
```
ThingsTasksContent.svelte (main orchestrator, ~200 lines)
├── ThingsTaskList.svelte (task list rendering, ~150 lines)
├── ThingsTaskItem.svelte (individual task, ~150 lines)
├── ThingsDraftForm.svelte (draft creation, ~150 lines)
└── lib/hooks/useThingsActions.ts (business logic, ~100 lines)
```

**Files to Create:**
- `frontend/src/lib/components/things/ThingsTaskList.svelte`
- `frontend/src/lib/components/things/ThingsTaskItem.svelte`
- `frontend/src/lib/components/things/ThingsDraftForm.svelte`
- `frontend/src/lib/hooks/useThingsActions.ts`

**Files to Modify:**
- `frontend/src/lib/components/things/ThingsTasksContent.svelte`

**Tests Required:**
- Unit tests for extracted components
- Integration test for ThingsTasksContent

**Estimated Effort:** 1.5 days
**Status:** Completed

---

##### 2e. `frontend/src/lib/components/chat/ChatWindow.svelte` (633 lines, limit: 600) ✅

**Issue:** SSE callback logic embedded in component.

**Solution:** Extract SSE handling to separate composable.

**Proposed Structure:**
```
ChatWindow.svelte (component logic, ~350 lines)
└── lib/composables/useChatSSE.ts (SSE callbacks, ~250 lines)
```

**Files to Create:**
- `frontend/src/lib/composables/useChatSSE.ts`

**Files to Modify:**
- `frontend/src/lib/components/chat/ChatWindow.svelte`

**Tests Required:**
- Unit tests for SSE callback logic
- Component tests for ChatWindow

**Estimated Effort:** 1 day
**Status:** Completed

---

##### 2f. `frontend/src/lib/components/left-sidebar/Sidebar.svelte` (624 lines, limit: 600) ✅

**Issue:** Multiple panel-specific logic in single component.

**Solution:** Extract panel-specific logic to dedicated components.

**Proposed Structure:**
```
Sidebar.svelte (layout orchestrator, ~250 lines)
├── NotesPanel.svelte (already exists, verify)
├── WebsitesPanel.svelte (already exists, verify)
├── FilesPanel.svelte (already exists, verify)
└── ThingsPanel.svelte (already exists, verify)
```

**Note:** If sub-components already exist, this might just be a matter of moving more logic out of parent.

**Files to Modify:**
- `frontend/src/lib/components/left-sidebar/Sidebar.svelte`
- Potentially the panel components

**Tests Required:**
- Component tests for Sidebar after extraction

**Estimated Effort:** 1 day
**Status:** Completed (LOC under limit)

---

### P0-3: Frontend API Proxy Duplication 🔄

**Problem:** 70 nearly identical API proxy files with duplicated error handling.

**Affected Files:** All files in `frontend/src/routes/api/*/+server.ts`

**Current Pattern** (repeated 70 times):
```typescript
// frontend/src/routes/api/notes/[id]/+server.ts
export const GET: RequestHandler = async ({ locals, fetch, params }) => {
  try {
    const response = await fetch(`${API_URL}/api/v1/notes/${params.id}`, {
      headers: buildAuthHeaders(locals)
    });
    if (!response.ok) {
      throw new Error(`Backend API error: ${response.statusText}`);
    }
    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to load note:', error);
    return json({ error: 'Failed to load note' }, { status: 500 });
  }
};
```

**Solution:** Create a generic proxy factory with centralized error handling.

```typescript
// frontend/src/lib/server/apiProxy.ts
import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

interface ProxyOptions {
  method?: string;
  pathBuilder: (params: Record<string, string>) => string;
  bodyFromRequest?: boolean;
  queryParamsFromUrl?: boolean;
}

export function createProxyHandler(options: ProxyOptions): RequestHandler {
  const {
    method = 'GET',
    pathBuilder,
    bodyFromRequest = false,
    queryParamsFromUrl = false
  } = options;

  return async ({ locals, fetch, params, request, url }) => {
    try {
      // Build backend URL
      const path = pathBuilder(params);
      let backendUrl = `${API_URL}${path}`;

      // Add query params if needed
      if (queryParamsFromUrl && url.search) {
        backendUrl += url.search;
      }

      // Build request options
      const requestOptions: RequestInit = {
        method,
        headers: buildAuthHeaders(locals)
      };

      // Add body if needed
      if (bodyFromRequest && method !== 'GET' && method !== 'HEAD') {
        requestOptions.body = await request.text();
        requestOptions.headers['Content-Type'] = request.headers.get('Content-Type') || 'application/json';
      }

      // Make request
      const response = await fetch(backendUrl, requestOptions);

      // Preserve status code from backend
      if (!response.ok) {
        const errorData = await response.json().catch(() => ({ error: response.statusText }));
        return json(errorData, { status: response.status });
      }

      // Return successful response
      const data = await response.json();
      return json(data, { status: response.status });

    } catch (err) {
      // Structured error logging
      console.error('API proxy error:', {
        path: pathBuilder(params),
        method,
        error: err
      });

      // Return error with appropriate status
      return json(
        { error: err instanceof Error ? err.message : 'Internal server error' },
        { status: 500 }
      );
    }
  };
}
```

**Usage in routes:**
```typescript
// frontend/src/routes/api/notes/[id]/+server.ts
import { createProxyHandler } from '$lib/server/apiProxy';

export const GET = createProxyHandler({
  pathBuilder: (params) => `/api/v1/notes/${params.id}`
});

export const PATCH = createProxyHandler({
  method: 'PATCH',
  pathBuilder: (params) => `/api/v1/notes/${params.id}`,
  bodyFromRequest: true
});

export const DELETE = createProxyHandler({
  method: 'DELETE',
  pathBuilder: (params) => `/api/v1/notes/${params.id}`
});
```

**Migration Strategy:**
1. Implement `apiProxy.ts` utility
2. Write comprehensive tests for proxy utility
3. Migrate routes one domain at a time (start with notes)
4. Verify each domain works before moving to next
5. Delete old proxy code once migrated

**Files to Create:**
- `frontend/src/lib/server/apiProxy.ts`

**Files to Modify:**
- All 70 files in `frontend/src/routes/api/*/+server.ts`

**Tests Required:**
- `frontend/src/tests/lib/server/apiProxy.test.ts` (comprehensive unit tests)
- Integration tests for critical API routes after migration

**Estimated Effort:** 2 days (1 day utility + tests, 1 day migration)
**Status:** In Progress
**Progress:** createProxyHandler supports json/text/stream response handling
**Completed Domains:** notes, websites, ingestion, files (partial), things, conversations, memories, scratchpad, chat generate-title, settings, settings shortcuts (PAT/rotate), skills, places, weather, Things bridge install script, notes/websites download
**Remaining:** chat stream, profile-image, v1 passthrough, files download, ingestion content, files content
**Risk:** Low - Centralized testing reduces risk, can migrate incrementally

---

### P0-4: UUID Validation Duplication ✅

**Problem:** UUID parsing repeated 20+ times across routers with inconsistent error messages.

**Examples:**
```python
# backend/api/routers/ingestion.py (9 occurrences)
try:
    file_uuid = uuid.UUID(file_id)
except ValueError as exc:
    raise BadRequestError("Invalid file_id") from exc

# backend/api/routers/notes.py (5 occurrences)
try:
    note_uuid = uuid.UUID(note_id)
except ValueError:
    raise BadRequestError("Invalid note id")

# backend/api/routers/websites.py (2 occurrences)
try:
    uuid.UUID(website_id)
except ValueError as exc:
    raise BadRequestError("Invalid website id") from exc
```

**Inconsistencies:**
- Error messages vary: "Invalid file_id" vs "Invalid file id" vs "Invalid note id"
- Some preserve exception chain (`from exc`), some don't
- Some services have helper methods (`parse_website_id()`, `NotesService.parse_note_id()`) but routes don't use them

**Solution:** Create centralized validation utility.

```python
# backend/api/utils/validation.py
"""Common validation utilities."""

import uuid
from typing import Optional
from backend.api.errors import BadRequestError

def parse_uuid(
    value: str,
    resource_name: str = "resource",
    field_name: str = "id"
) -> uuid.UUID:
    """
    Parse a UUID string with consistent error handling.

    Args:
        value: The string to parse as UUID
        resource_name: Name of resource for error message (e.g., "note", "file")
        field_name: Name of field for error message (default: "id")

    Returns:
        Parsed UUID object

    Raises:
        BadRequestError: If value is not a valid UUID

    Example:
        >>> note_id = parse_uuid(note_id_str, "note")
        >>> file_id = parse_uuid(file_id_str, "file", "file_id")
    """
    try:
        return uuid.UUID(value)
    except (ValueError, TypeError, AttributeError) as exc:
        raise BadRequestError(
            f"Invalid {resource_name} {field_name}: must be a valid UUID"
        ) from exc

def parse_optional_uuid(
    value: Optional[str],
    resource_name: str = "resource",
    field_name: str = "id"
) -> Optional[uuid.UUID]:
    """
    Parse an optional UUID string.

    Returns None if value is None, otherwise delegates to parse_uuid.
    """
    if value is None:
        return None
    return parse_uuid(value, resource_name, field_name)
```

**Migration Strategy:**
1. Create validation utility with tests
2. Update routers one at a time:
   - Replace inline UUID parsing with utility call
   - Standardize error messages
3. Remove unused service-level parse methods (or update them to use utility)

**Usage Examples:**
```python
# backend/api/routers/notes.py
from backend.api.utils.validation import parse_uuid

@router.get("/{note_id}")
async def get_note(
    note_id: str,
    user_id: str = Depends(get_user_id),
    db: Session = Depends(get_db),
):
    note_uuid = parse_uuid(note_id, "note")  # Consistent error handling
    note = NotesService.get_note_by_id(db, note_uuid, user_id)
    # ...
```

**Files to Create:**
- `backend/api/utils/validation.py`

**Files to Modify:**
- `backend/api/routers/ingestion.py` (9 replacements)
- `backend/api/routers/notes.py` (5 replacements)
- `backend/api/routers/websites.py` (2 replacements)
- `backend/api/routers/conversations.py`
- `backend/api/routers/chat.py`
- Other routers with UUID parsing

**Tests Required:**
- `backend/tests/test_validation.py` (comprehensive unit tests for parse_uuid)
- Verify existing router tests still pass

**Estimated Effort:** 0.5 days
**Status:** Completed
**Risk:** Low - Simple utility, well-tested

---

## Medium Priority Items

### P1-1: Error Handling Standardization

**Problem:** 161 console.error statements across frontend with generic messages. No structured error logging or status code preservation.

**Examples:**
```typescript
// Generic error messages don't help debugging
catch (error) {
    console.error('Failed to load note:', error);
    return json({ error: 'Failed to load note' }, { status: 500 });
}

// Loses backend HTTP status code context
catch (error) {
    return json({ error: 'Failed' }, { status: 500 });
    // Backend might have returned 404, 403, or 400
}
```

**Solution:** Create centralized error handling utilities.

**Note:** This is partially addressed by P0-3 (API Proxy), which centralizes error handling for API routes. This item focuses on client-side error handling in components and stores.

```typescript
// frontend/src/lib/utils/errorHandling.ts
import { error as svelteKitError } from '@sveltejs/kit';

export interface StructuredError {
  message: string;
  status: number;
  code?: string;
  context?: Record<string, any>;
}

export class APIError extends Error {
  status: number;
  code?: string;
  context?: Record<string, any>;

  constructor(error: StructuredError) {
    super(error.message);
    this.name = 'APIError';
    this.status = error.status;
    this.code = error.code;
    this.context = error.context;
  }
}

/**
 * Log errors with structured context for better debugging.
 */
export function logError(
  message: string,
  error: unknown,
  context?: Record<string, any>
): void {
  console.error(message, {
    error: error instanceof Error ? {
      name: error.name,
      message: error.message,
      stack: error.stack
    } : error,
    context,
    timestamp: new Date().toISOString()
  });
}

/**
 * Extract error information from various error types.
 */
export function parseError(error: unknown): StructuredError {
  if (error instanceof APIError) {
    return {
      message: error.message,
      status: error.status,
      code: error.code,
      context: error.context
    };
  }

  if (error instanceof Error) {
    return {
      message: error.message,
      status: 500
    };
  }

  return {
    message: 'An unexpected error occurred',
    status: 500
  };
}

/**
 * Handle fetch errors with proper status code extraction.
 */
export async function handleFetchError(response: Response): Promise<never> {
  const errorData = await response.json().catch(() => ({
    error: response.statusText
  }));

  throw new APIError({
    message: errorData.error || errorData.message || 'Request failed',
    status: response.status,
    code: errorData.code,
    context: errorData.context
  });
}
```

**Usage in components:**
```typescript
// Before
try {
  const response = await fetch(`/api/notes/${id}`);
  if (!response.ok) throw new Error('Failed to load note');
  return await response.json();
} catch (error) {
  console.error('Failed to load note:', error);
  throw error;
}

// After
import { logError, handleFetchError } from '$lib/utils/errorHandling';

try {
  const response = await fetch(`/api/notes/${id}`);
  if (!response.ok) await handleFetchError(response);
  return await response.json();
} catch (error) {
  logError('Note fetch failed', error, { noteId: id });
  throw error;
}
```

**Migration Strategy:**
1. Create error handling utilities with tests
2. Update stores first (more complex error handling)
3. Update components incrementally
4. Monitor error logs to ensure improvements

**Files to Create:**
- `frontend/src/lib/utils/errorHandling.ts`

**Files to Modify:**
- Stores in `frontend/src/lib/stores/`
- Components with fetch logic
- API route handlers (if not covered by P0-3)

**Tests Required:**
- `frontend/src/tests/utils/errorHandling.test.ts`

**Estimated Effort:** 2 days (1 day utility + tests, 1 day migration)
**Risk:** Low - Incremental rollout, backwards compatible

---

### P1-2: JSONB Update Audit

**Problem:** JSONB fields require `flag_modified()` to persist updates, but not all update locations might be using it correctly.

**Current Status:**
- ✅ 14 confirmed uses of `flag_modified()`
- ⚠️ Need to audit all JSONB write locations

**JSONB Fields in Models:**
- `Conversation.messages` (JSONB)
- `Note.metadata_` (JSONB)
- `Website.metadata_` (JSONB)
- `IngestedFile.metadata_` (JSONB)
- `UserSettings.settings` (JSONB)

**Solution:** Comprehensive audit and optional helper utilities.

**Audit Process:**
1. Search for all assignments to JSONB fields: `\.messages\[`, `\.metadata_\[`, `\.settings\[`
2. Verify each assignment is followed by `flag_modified()` call
3. Check for indirect updates (function calls that modify JSONB)
4. Add missing `flag_modified()` calls

**Optional Helper Utility:**
```python
# backend/api/utils/jsonb.py
from contextlib import contextmanager
from sqlalchemy.orm.attributes import flag_modified
from typing import TypeVar, Generic

T = TypeVar('T')

class JSONBField(Generic[T]):
    """
    Helper for safe JSONB field updates.

    Usage:
        note.metadata = JSONBField(note, 'metadata_', note.metadata_)
        note.metadata['pinned'] = True
        note.metadata.save()  # Automatically calls flag_modified
    """
    def __init__(self, instance, field_name: str, data: T):
        self._instance = instance
        self._field_name = field_name
        self._data = data

    def __getitem__(self, key):
        return self._data[key]

    def __setitem__(self, key, value):
        self._data[key] = value

    def save(self):
        """Persist changes to JSONB field."""
        flag_modified(self._instance, self._field_name)

@contextmanager
def jsonb_update(instance, field_name: str):
    """
    Context manager for JSONB updates.

    Usage:
        with jsonb_update(note, 'metadata_'):
            note.metadata_['pinned'] = True
            note.metadata_['order'] = 5
        # flag_modified called automatically on exit
    """
    yield
    flag_modified(instance, field_name)
```

**Migration Strategy:**
1. Run comprehensive search for JSONB field updates
2. Document all update locations
3. Verify `flag_modified()` usage in each
4. Add missing calls
5. (Optional) Implement helper utilities if pattern is common
6. Add linting rule or pre-commit hook to catch future violations

**Files to Audit:**
- `backend/api/services/*.py` (all services)
- `backend/api/routers/*.py` (check for any direct updates)

**Tests Required:**
- Add regression tests for JSONB updates without `flag_modified()`
- Test helper utilities if implemented

**Estimated Effort:** 1 day (audit + fixes)
**Risk:** Medium - Missing `flag_modified()` causes silent data loss

---

## Low Priority Items

### P2-1: Component Event Handler Extraction

**Problem:** Large components have inline event handlers that mix business logic with UI, making them hard to test.

**Pattern:**
```svelte
<!-- WebsitesPanel.svelte, FilesPanelController.svelte, NotesPanel.svelte -->
<script>
async function handleRename(item) {
  try {
    const response = await fetch(`/api/websites/${item.id}/rename`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: newTitle })
    });
    if (!response.ok) throw new Error('Failed to rename');
    // Update local state
    items = items.map(i => i.id === item.id ? { ...i, title: newTitle } : i);
  } catch (error) {
    console.error('Failed to rename:', error);
  }
}

async function handlePin(item) { /* similar */ }
async function handleArchive(item) { /* similar */ }
async function handleDelete(item) { /* similar */ }
</script>
```

**Solution:** Extract to composable action hooks (some already exist).

**Existing Patterns:**
- `frontend/src/lib/hooks/useFileActions.ts`
- `frontend/src/lib/hooks/useEditorActions.ts`

**Expand to:**
- `frontend/src/lib/hooks/useWebsiteActions.ts`
- `frontend/src/lib/hooks/useNoteActions.ts`
- `frontend/src/lib/hooks/useThingsActions.ts`

**Example Hook:**
```typescript
// frontend/src/lib/hooks/useWebsiteActions.ts
import { writable } from 'svelte/store';
import type { Website } from '$lib/types';

export function useWebsiteActions() {
  const loading = writable(false);
  const error = writable<string | null>(null);

  async function rename(websiteId: string, newTitle: string): Promise<Website> {
    loading.set(true);
    error.set(null);

    try {
      const response = await fetch(`/api/websites/${websiteId}/rename`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title: newTitle })
      });

      if (!response.ok) {
        throw new Error('Failed to rename website');
      }

      return await response.json();
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'Unknown error';
      error.set(errorMessage);
      throw err;
    } finally {
      loading.set(false);
    }
  }

  async function pin(websiteId: string): Promise<void> {
    // Similar pattern
  }

  async function archive(websiteId: string): Promise<void> {
    // Similar pattern
  }

  async function deleteWebsite(websiteId: string): Promise<void> {
    // Similar pattern
  }

  return {
    loading,
    error,
    rename,
    pin,
    archive,
    delete: deleteWebsite
  };
}
```

**Usage in components:**
```svelte
<script lang="ts">
import { useWebsiteActions } from '$lib/hooks/useWebsiteActions';

const actions = useWebsiteActions();

async function handleRename(item) {
  try {
    const updated = await actions.rename(item.id, newTitle);
    // Update local state
    items = items.map(i => i.id === updated.id ? updated : i);
  } catch (error) {
    // Error already logged in hook
  }
}
</script>

{#if $actions.loading}
  <Spinner />
{/if}
```

**Benefits:**
- Business logic testable independently
- Consistent error handling
- Loading state management
- Reusable across components

**Migration Strategy:**
1. Create hooks for each domain (websites, notes, things, files)
2. Write comprehensive tests for hooks
3. Update components to use hooks
4. Remove inline event handlers

**Files to Create:**
- `frontend/src/lib/hooks/useWebsiteActions.ts`
- `frontend/src/lib/hooks/useNoteActions.ts`
- `frontend/src/lib/hooks/useThingsActions.ts`

**Files to Modify:**
- `frontend/src/lib/components/panels/WebsitesPanel.svelte`
- `frontend/src/lib/components/panels/NotesPanel.svelte`
- `frontend/src/lib/components/things/ThingsTasksContent.svelte`
- Other components with event handlers

**Tests Required:**
- Unit tests for all hooks
- Component tests updated to use hooks

**Estimated Effort:** 2 days
**Risk:** Low - Improves testability, incremental rollout

---

### P2-2: Naming Consistency

**Problem:** Inconsistent naming conventions across codebase.

**Examples:**
- Error messages: "Invalid file_id" vs "Invalid file id" vs "Invalid note id"
- Some use underscore, some use space
- Inconsistent capitalization

**Solution:** Establish and document naming conventions.

**Proposed Conventions:**
```python
# Python (AGENTS.md already specifies snake_case)
- Variables: snake_case
- Functions: snake_case
- Classes: PascalCase
- Constants: SCREAMING_SNAKE_CASE
- Error messages: "Invalid {resource} ID" (capitalized ID, no underscore)

# TypeScript (AGENTS.md already specifies camelCase)
- Variables: camelCase
- Functions: camelCase
- Components: PascalCase
- Types/Interfaces: PascalCase
- Constants: SCREAMING_SNAKE_CASE
- Error messages: "Invalid {resource} ID"
```

**Migration Strategy:**
1. Document conventions in AGENTS.md (if not already there)
2. Fix high-visibility items (error messages, public APIs)
3. Address remaining items during regular refactoring
4. Add linting rules to enforce (ESLint for TS, ruff for Python)

**Estimated Effort:** 0.5 days (documentation + high-priority fixes)
**Risk:** Very Low - Cosmetic changes, no logic impact

---

### P2-3: Helper Function Organization

**Problem:** Router helper functions duplicated or inconsistently organized.

**Examples:**
- `ingestion.py` has 9 helper functions prefixed with `_`
- `websites.py` has helper functions
- `notes.py` uses service layer methods (better pattern)

**Solution:** Consolidate helpers into domain-specific modules.

**Strategy:**
1. Extract router helpers to `{domain}_helpers.py` modules
2. Convert service-level helpers to proper service methods
3. Delete unused helpers

**Files to Create/Modify:**
- `backend/api/routers/ingestion_helpers.py` (from P0-2a)
- `backend/api/routers/websites_helpers.py`
- Other router helper modules as needed

**Estimated Effort:** 1 day (part of P0-2a work)
**Risk:** Low - Internal refactoring

---

## Implementation Phases

### Phase 1: Critical Compliance (Week 1-2)

**Goal:** Fix AGENTS.md constraint violations and architecture issues.

**Tasks:**
1. **P0-1:** Move DB queries to services (3 days)
   - Create service methods with tests
   - Update routers to use services
   - Verify integration tests pass

2. **P0-2a:** Extract ingestion.py helpers (1 day)
   - Create ingestion_helpers.py
   - Move helper functions
   - Update tests

3. **P0-4:** Centralize UUID validation (0.5 days)
   - Create validation utility
   - Write comprehensive tests
   - Update routers incrementally

**Deliverables:**
- All routers use service layer for DB access ✅
- ingestion.py under 500 LOC limit ✅
- Consistent UUID validation across backend ✅

**Success Criteria:**
- All tests pass
- No AGENTS.md violations in modified files
- Code review approval

---

### Phase 2: Backend Refactoring (Week 3)

**Goal:** Complete backend file size fixes and improve maintainability.

**Tasks:**
1. **P0-2b:** Refactor parameter_mapper.py (2 days)
   - Create parameter builder classes
   - Write comprehensive tests
   - Migrate builders incrementally
   - Update imports

2. **P0-2c:** Extract file search service (1 day)
   - Create file_search_service.py
   - Move search logic
   - Update tests

3. **P1-2:** JSONB update audit (1 day)
   - Audit all JSONB update locations
   - Add missing flag_modified() calls
   - Write regression tests

**Deliverables:**
- parameter_mapper.py split into cohesive builder classes ✅
- skill_file_ops_ingestion.py under 600 LOC limit ✅
- All JSONB updates use flag_modified() 🔄 (audit pending)

**Success Criteria:**
- All backend files meet LOC limits
- No missing flag_modified() calls
- Test coverage maintained or improved

---

### Phase 3: Frontend Duplication Elimination (Week 4)

**Goal:** Eliminate massive frontend duplication.

**Tasks:**
1. **P0-3:** Create API proxy utility (2 days)
   - Implement createProxyHandler
   - Write comprehensive tests
   - Migrate API routes incrementally
   - Verify each domain works

2. **P0-2d/e/f:** Frontend component splitting (3 days)
   - Split ThingsTasksContent.svelte (1.5 days)
   - Extract ChatWindow SSE logic (1 day)
   - Refactor Sidebar.svelte (0.5 days)

**Deliverables:**
- 70 API proxy files replaced with utility 🔄 (in progress)
- All frontend components under 600 LOC limit ✅
- Improved testability 🔄

**Success Criteria:**
- API proxy handles all HTTP methods and status codes
- Component tests pass
- No regression in functionality

---

### Phase 4: Quality & Polish (Week 5+)

**Goal:** Standardize patterns and improve code quality.

**Tasks:**
1. **P1-1:** Error handling standardization (2 days)
   - Create error utilities
   - Update stores and components
   - Improve error logging

2. **P2-1:** Component event handler extraction (2 days)
   - Create domain-specific action hooks
   - Write hook tests
   - Update components to use hooks

3. **P2-2:** Naming consistency (0.5 days)
   - Document conventions
   - Fix high-priority inconsistencies
   - Add linting rules

**Deliverables:**
- Consistent error handling across frontend
- Testable business logic in hooks
- Documented naming conventions

**Success Criteria:**
- Improved debugging with structured errors
- Higher test coverage for business logic
- Linting enforces conventions

---

## Success Metrics

### Compliance Metrics
- ✅ Zero files exceeding LOC limits (currently 6 violations)
- ✅ Zero DB queries in routers (currently 5+ violations)
- ✅ All JSONB updates use flag_modified() (currently unknown)

### Code Quality Metrics
- ✅ Backend duplication: UUID validation consolidated (20+ → 1)
- ✅ Frontend duplication: API proxies consolidated (70 → 1 utility)
- ✅ Parameter builders organized into classes (40+ functions → 5-6 classes)

### Maintainability Metrics
- ✅ Largest backend file: <600 LOC (currently 692)
- ✅ Largest frontend component: <600 LOC (currently 689)
- ✅ Average file size reduction: 20%+

### Testing Metrics
- ✅ Test coverage maintained or improved (>80% backend, >70% frontend)
- ✅ All new utilities have >90% test coverage
- ✅ Zero regression bugs in production

### Developer Experience Metrics
- ✅ Consistent error messages across codebase
- ✅ Reusable hooks for common operations
- ✅ Clear separation of concerns (UI vs business logic)

---

## Risks & Mitigation

### Risk 1: Breaking Changes During Refactoring
**Likelihood:** Medium
**Impact:** High
**Mitigation:**
- TDD approach - write tests before refactoring
- Incremental migration - one file/domain at a time
- Comprehensive integration tests before merging
- Staged rollout to production

### Risk 2: Incomplete JSONB Audit
**Likelihood:** Medium
**Impact:** Medium (silent data loss)
**Mitigation:**
- Systematic search for all JSONB field access
- Peer review of audit findings
- Add regression tests for JSONB updates
- Monitor production logs for unexpected behavior

### Risk 3: API Proxy Utility Missing Edge Cases
**Likelihood:** Low
**Impact:** Medium
**Mitigation:**
- Comprehensive test suite (happy path + errors)
- Test with all HTTP methods and status codes
- Incremental migration with verification
- Rollback plan if issues discovered

### Risk 4: Large Components Hard to Split
**Likelihood:** Low
**Impact:** Low
**Mitigation:**
- Start with clearest separation (ThingsTasksContent)
- Extract logic incrementally, not all at once
- Maintain component tests throughout
- Accept temporary duplication during migration

### Risk 5: Time Estimation Accuracy
**Likelihood:** Medium
**Impact:** Low (schedule slip)
**Mitigation:**
- Buffer time in estimates (already conservative)
- Prioritize P0 items - P1/P2 can slip if needed
- Regular progress check-ins
- Scope reduction if timeline critical

---

## Review & Approval

**Document Owner:** Development Team
**Review Cycle:** Before starting each phase
**Approval Required From:**
- Technical Lead (architecture decisions)
- QA Lead (testing strategy)
- Product Owner (timeline and priorities)

---

## Appendix: Affected Files Summary

### Backend Files (Core)
- `backend/api/routers/ingestion.py` (P0-1, P0-2a)
- `backend/api/routers/chat.py` (P0-1)
- `backend/api/routers/memories.py` (P0-1)
- `backend/api/routers/conversations.py` (P0-1)
- `backend/api/routers/websites.py` (P0-1, P0-4)
- `backend/api/routers/notes.py` (P0-4)
- `backend/api/services/tools/parameter_mapper.py` (P0-2b)
- `backend/api/services/skill_file_ops_ingestion.py` (P0-2c)
- All services (P1-2 JSONB audit)

### Backend Files (New)
- `backend/api/routers/ingestion_helpers.py` (P0-2a)
- `backend/api/utils/validation.py` (P0-4)
- `backend/api/services/file_search_service.py` (P0-2c)
- `backend/api/services/tools/parameter_builders/` (directory, P0-2b)
- `backend/api/utils/jsonb.py` (optional, P1-2)

### Frontend Files (Core)
- All 70 files in `frontend/src/routes/api/*/+server.ts` (P0-3)
- `frontend/src/lib/components/things/ThingsTasksContent.svelte` (P0-2d)
- `frontend/src/lib/components/chat/ChatWindow.svelte` (P0-2e)
- `frontend/src/lib/components/left-sidebar/Sidebar.svelte` (P0-2f)
- Components with event handlers (P2-1)
- All stores (P1-1)

### Frontend Files (New)
- `frontend/src/lib/server/apiProxy.ts` (P0-3)
- `frontend/src/lib/composables/useChatSSE.ts` (P0-2e)
- `frontend/src/lib/components/things/ThingsTaskList.svelte` (P0-2d)
- `frontend/src/lib/components/things/ThingsTaskItem.svelte` (P0-2d)
- `frontend/src/lib/components/things/ThingsDraftForm.svelte` (P0-2d)
- `frontend/src/lib/utils/errorHandling.ts` (P1-1)
- `frontend/src/lib/hooks/useWebsiteActions.ts` (P2-1)
- `frontend/src/lib/hooks/useNoteActions.ts` (P2-1)
- `frontend/src/lib/hooks/useThingsActions.ts` (P2-1)

### Test Files (New/Modified)
- `backend/tests/test_validation.py` (P0-4)
- `backend/tests/test_file_search_service.py` (P0-2c)
- `backend/tests/test_parameter_builders.py` (P0-2b)
- `backend/tests/test_ingestion_helpers.py` (P0-2a)
- `frontend/src/tests/lib/server/apiProxy.test.ts` (P0-3)
- `frontend/src/tests/utils/errorHandling.test.ts` (P1-1)
- Component/service tests updated throughout

---

**Last Updated:** 2026-01-04
**Status:** Ready for Review
