# Refactoring Backlog

**Date Created:** 2026-01-05
**Last Updated:** 2026-01-05 (Completed MED-1 and MED-2)
**Status:** Active

This document tracks refactoring opportunities identified during code reviews. Items are prioritized and tracked to completion.

---

## Table of Contents

- [Critical Priority](#critical-priority)
- [High Priority](#high-priority)
- [Medium Priority](#medium-priority)
- [Low Priority](#low-priority)
- [Deferred Items](#deferred-items)

---

## How to Use This Document

- **Priority levels**: Critical → High → Medium → Low
- **Status**: 🔴 Not Started | 🟡 In Progress | ⏸️ Deferred
- **Effort**: S (< 1 day) | M (1-3 days) | L (3-5 days) | XL (> 1 week)
- **Impact**: What breaks or degrades if not fixed

When starting work on an item:
1. Change status to 🟡 In Progress
2. Add your name and date
3. Create a branch if needed
4. Update "Last Updated" date at top
5. Delete the item when completed (git history preserves the record)

---

## Critical Priority

**All critical items have been resolved! 🎉**

---

## High Priority

Issues that cause bugs, performance problems, or significant maintainability concerns.

## Medium Priority

Issues that impact code quality, consistency, or maintainability but don't cause immediate problems.

### 🔴 MED-3: Inconsistent API Response Formats
**Status:** 🔴 Not Started
**Effort:** M (2 days)
**Impact:** Frontend needs to handle multiple response formats, harder to maintain

**Location:**
- `backend/api/routers/conversations.py:137`
- `backend/api/routers/notes.py:345`
- `backend/api/routers/websites.py:239`

**Description:**
Update/action endpoints return inconsistent response structures:

```python
# Pattern 1: Simple success
return {"success": True}

# Pattern 2: Success with data
return {"success": True, "messageCount": conversation.message_count}

# Pattern 3: Return updated resource
return updated_note

# Pattern 4: HTTP 204 No Content
return Response(status_code=204)
```

**Issues:**
- Frontend must handle 4+ response patterns
- Harder to create generic API utilities
- Inconsistent error handling
- Testing complexity

**Recommended Solution:**

**Option 1: Always return updated resource**
```python
# Most RESTful approach
@router.patch("/{note_id}")
async def update_note(...) -> NoteResponse:
    note = NotesService.update_note(...)
    return NoteResponse.from_orm(note)
```

**Option 2: Standardize success responses**
```python
# backend/api/schemas/common.py
class ActionResponse(BaseModel):
    """Standard response for update/delete actions."""
    success: bool = True
    message: Optional[str] = None
    data: Optional[dict] = None

@router.patch("/{note_id}")
async def update_note(...) -> ActionResponse:
    note = NotesService.update_note(...)
    return ActionResponse(
        success=True,
        message="Note updated",
        data={"id": str(note.id), "updated_at": note.updated_at}
    )
```

**Option 3: Use HTTP 204 for updates**
```python
# Cleanest for updates without response data
@router.patch("/{note_id}", status_code=204)
async def update_note(...) -> None:
    NotesService.update_note(...)
    return Response(status_code=204)
```

**Recommendation:** Choose **Option 1** (return updated resource) for consistency with REST principles and ease of use.

**Files to Review:**
- All routers in `backend/api/routers/`
- Document decision in API.md

**Tests to Update:**
- Frontend API tests
- Integration tests for all endpoints

**Breaking Change:** Yes - requires frontend updates

**Assigned to:** _Unassigned_
**Date Started:** _Not started_

---

### 🔴 MED-4: Magic Numbers Without Documentation
**Status:** 🔴 Not Started
**Effort:** S (1 day)
**Impact:** Hard to understand why limits were chosen, difficult to tune

**Location:**
- `backend/api/routers/chat.py:30-31,129`
- `backend/api/services/claude_streaming.py:55`
- `backend/api/services/prompt_context_service.py:31-34`

**Description:**
Magic numbers scattered throughout code:

```python
# Why these specific values?
TITLE_CACHE_TTL_SECONDS = 60 * 60  # 1 hour
TITLE_CACHE_MAX_ENTRIES = 512      # 512 entries
if len(words) > 5:                 # 5 words
max_rounds = 5                     # 5 rounds
```

**Issues:**
- No explanation for chosen values
- Hard to tune without understanding constraints
- Cannot easily share limits across modules
- Future maintainers won't know reasoning

**Recommended Solution:**

```python
# backend/api/config.py (or new constants.py)

class ChatConstants:
    """Chat-related configuration constants."""

    # Title generation
    TITLE_CACHE_TTL_SECONDS = 3600  # 1 hour
    """
    Cache title generation results for 1 hour.
    Rationale: Titles rarely need regeneration, and caching reduces
    API calls to Gemini. 1 hour balances freshness vs API cost.
    """

    TITLE_CACHE_MAX_ENTRIES = 512
    """
    LRU cache size for title generation.
    Rationale: Based on memory constraints (512 * ~100 bytes = ~50KB).
    Covers typical user's recent conversations without excessive memory.
    """

    TITLE_MAX_WORDS = 5
    """
    Maximum words in generated title.
    Rationale: UI design shows max 50 characters. Average word length
    ~5 chars, so 5 words ≈ 25-30 chars with spaces. Keeps titles concise.
    """

    MAX_TOOL_ROUNDS = 5
    """
    Maximum tool use iterations per message.
    Rationale: Prevents infinite loops while allowing complex multi-step
    operations. Based on testing, 95% of valid tool use completes within
    3 rounds. 5 provides safety margin.
    """

# Usage:
from api.config import ChatConstants

if len(words) > ChatConstants.TITLE_MAX_WORDS:
    title = " ".join(words[:ChatConstants.TITLE_MAX_WORDS])
```

**Files to Modify:**
- `backend/api/config.py` or create `backend/api/constants.py`
- `backend/api/routers/chat.py`
- `backend/api/services/claude_streaming.py`
- `backend/api/services/prompt_context_service.py`

**Benefits:**
- Centralized configuration
- Documented reasoning
- Easier to tune via environment variables
- Better code readability

**Assigned to:** _Unassigned_
**Date Started:** _Not started_

---

### 🔴 MED-6: Inconsistent User ID Injection Logic
**Status:** 🔴 Not Started
**Effort:** M (2 days)
**Impact:** Easy to forget user_id for new tools, potential security issue

**Location:**
- `backend/api/services/tool_mapper.py:177-196`
- `backend/api/services/tools/parameter_builders/notes_builder.py`

**Description:**
User ID injection is handled inconsistently in multiple places:

```python
# In tool_mapper.py lines 177-196 - first injection
if context and tool_config.get("skill") in {
    "fs", "notes", "web-save", ...
}:
    user_id = context.get("user_id")
    if user_id:
        parameters = {**parameters, "user_id": user_id}

# Then again in tool_mapper.py lines 183-195 - second injection
if parameters.get("user_id") and tool_config.get("skill") in {...}:
    if "--user-id" not in args:
        args.extend(["--user-id", parameters["user_id"]])

# And also in parameter builders
NotesParameterBuilder.append_user_id(args, params)
```

**Issues:**
- Duplicate skill set definitions
- Easy to add new tool and forget user_id
- Security risk if user_id missing for authenticated tools
- Logic scattered across 3 places

**Recommended Solution:**

```python
# Define once at top of tool_mapper.py
SKILLS_REQUIRING_USER_ID = {
    "fs", "pdf", "pptx", "docx", "xlsx",
    "youtube-download", "youtube-transcribe",
    "audio-transcribe", "web-crawler-policy",
    "notes", "web-save"
}

# Consolidate injection in one place
def inject_user_id(tool_config: dict, parameters: dict, context: dict) -> dict:
    """
    Inject user_id into parameters if skill requires it.

    Raises ValueError if skill requires user_id but context missing it.
    """
    skill = tool_config.get("skill")

    if skill not in SKILLS_REQUIRING_USER_ID:
        return parameters

    user_id = context.get("user_id")
    if not user_id:
        raise ValueError(f"Skill '{skill}' requires user_id in context")

    return {**parameters, "user_id": user_id}

# Use consistently
parameters = inject_user_id(tool_config, parameters, context)
```

**Files to Modify:**
- `backend/api/services/tool_mapper.py`
- Parameter builders (remove duplicate logic)

**Tests:**
- Verify user_id injection for all required skills
- Test error when user_id missing
- Verify non-auth tools don't get user_id

**Assigned to:** _Unassigned_
**Date Started:** _Not started_

---

### 🔴 MED-7: Primitive Obsession - Tool Context
**Status:** 🔴 Not Started
**Effort:** M (2 days)
**Impact:** No type safety, easy to misspell keys, hard to refactor

**Location:**
- `backend/api/routers/chat.py:225-235`
- `backend/api/services/claude_streaming.py:23`

**Description:**
Tool context passed as `Dict[str, Any]` throughout codebase:

```python
tool_context = {
    "db": db,
    "user_id": user_id,
    "open_context": open_context,
    "attachments": attachments,
    "conversation_id": str(conversation_uuid),
    "user_message_id": str(user_message_id),
    "assistant_message_id": str(assistant_message_id),
    "notes_context": notes_context,
}
```

**Issues:**
- No type hints
- Easy to typo keys: `user_id` vs `userId` vs `user-id`
- Hard to know what fields are available
- No IDE autocomplete
- Difficult to refactor

**Recommended Solution:**

```python
# backend/api/schemas/tool_context.py
from dataclasses import dataclass, field
from typing import Optional, Any
from uuid import UUID
from sqlalchemy.orm import Session

@dataclass
class ToolExecutionContext:
    """Context passed to tool execution."""

    # Required fields
    db: Session
    user_id: str

    # Optional fields
    open_context: Optional[dict[str, Any]] = None
    attachments: list[dict[str, Any]] = field(default_factory=list)
    conversation_id: Optional[UUID] = None
    user_message_id: Optional[UUID] = None
    assistant_message_id: Optional[UUID] = None
    notes_context: Optional[str] = None

    def to_dict(self) -> dict[str, Any]:
        """Convert to dict for backward compatibility."""
        return {
            "db": self.db,
            "user_id": self.user_id,
            "open_context": self.open_context,
            "attachments": self.attachments,
            "conversation_id": str(self.conversation_id) if self.conversation_id else None,
            "user_message_id": str(self.user_message_id) if self.user_message_id else None,
            "assistant_message_id": str(self.assistant_message_id) if self.assistant_message_id else None,
            "notes_context": self.notes_context,
        }

# Usage:
from api.schemas.tool_context import ToolExecutionContext

tool_context = ToolExecutionContext(
    db=db,
    user_id=user_id,
    open_context=open_context,
    attachments=attachments,
    conversation_id=conversation_uuid,
    user_message_id=user_message_id,
    assistant_message_id=assistant_message_id,
    notes_context=notes_context,
)

# Pass to streaming
await ClaudeStreamingService.stream_chat(
    ...,
    context=tool_context.to_dict()  # Convert for backward compat
)
```

**Migration Strategy:**
1. Create `ToolExecutionContext` dataclass
2. Update routers to build context object
3. Convert to dict when passing to existing code
4. Gradually update services to accept dataclass directly
5. Remove `to_dict()` once migration complete

**Files to Create:**
- `backend/api/schemas/tool_context.py`

**Files to Modify:**
- `backend/api/routers/chat.py`
- `backend/api/services/claude_streaming.py`
- `backend/api/services/tool_mapper.py`

**Benefits:**
- Type safety
- IDE autocomplete
- Easier refactoring
- Self-documenting code

**Assigned to:** _Unassigned_
**Date Started:** _Not started_

---

## Low Priority

Nice-to-have improvements that don't significantly impact functionality.

### 🔴 LOW-1: Long Parameter Lists in Filter Methods
**Status:** 🔴 Not Started
**Effort:** M (2 days)
**Impact:** Hard to remember parameter order, cluttered signatures

**Location:**
- `backend/api/services/notes_service.py` `list_notes()` (9 optional params)
- `backend/api/services/websites_service.py` `list_websites()` (11 optional params)

**Description:**
Filter methods have very long parameter lists:

```python
def list_notes(
    db: Session,
    user_id: str,
    *,
    folder: Optional[str] = None,
    pinned: Optional[bool] = None,
    archived: Optional[bool] = None,
    created_after: Optional[datetime] = None,
    created_before: Optional[datetime] = None,
    updated_after: Optional[datetime] = None,
    updated_before: Optional[datetime] = None,
    opened_after: Optional[datetime] = None,
    opened_before: Optional[datetime] = None,
    title_search: Optional[str] = None,
) -> Iterable[Note]:
```

**Recommended Solution:**

```python
# backend/api/schemas/filters.py
from dataclasses import dataclass
from typing import Optional
from datetime import datetime

@dataclass
class NoteFilters:
    """Filters for listing notes."""
    folder: Optional[str] = None
    pinned: Optional[bool] = None
    archived: Optional[bool] = None
    created_after: Optional[datetime] = None
    created_before: Optional[datetime] = None
    updated_after: Optional[datetime] = None
    updated_before: Optional[datetime] = None
    opened_after: Optional[datetime] = None
    opened_before: Optional[datetime] = None
    title_search: Optional[str] = None

# Then:
def list_notes(
    db: Session,
    user_id: str,
    filters: NoteFilters
) -> Iterable[Note]:
    """List notes with optional filters."""
    query = db.query(Note).filter(Note.user_id == user_id)

    if filters.folder:
        query = query.filter(Note.folder == filters.folder)
    if filters.pinned is not None:
        # ...
```

**Benefits:**
- Cleaner method signatures
- Easy to add new filters
- Can validate filters in dataclass
- Better for API endpoints (can use Pydantic)

**Files to Create:**
- `backend/api/schemas/filters.py`

**Files to Modify:**
- `backend/api/services/notes_service.py`
- `backend/api/services/websites_service.py`
- `backend/api/routers/notes.py`
- `backend/api/routers/websites.py`

**Assigned to:** _Unassigned_
**Date Started:** _Not started_

---

### 🔴 LOW-2: UUID Type Inconsistency in Routers
**Status:** 🔴 Not Started
**Effort:** S (1 day)
**Impact:** Inconsistent API design, duplicate validation

**Description:**
Some routers use FastAPI's native `UUID` type parameter, others accept `str` and parse manually:

```python
# Pattern 1: Native UUID type
async def get_conversation(conversation_id: UUID, ...):

# Pattern 2: String with manual parsing
async def get_website(website_id: str, ...):
    website_uuid = parse_uuid(website_id, "website", "id")
```

**Recommended Solution:**
Standardize on FastAPI's `UUID` type for path parameters - it provides automatic validation and consistent error messages.

**Files to Review:**
- All routers in `backend/api/routers/`

**Assigned to:** _Unassigned_
**Date Started:** _Not started_

---

### 🔴 LOW-3: Missing Logging Context in Services
**Status:** 🔴 Not Started
**Effort:** M (ongoing)
**Impact:** Harder to debug production issues

**Description:**
Error handling catches exceptions but doesn't log them with sufficient context (user_id, resource_id, operation).

**Recommended Pattern:**

```python
try:
    # operation
except Exception as e:
    logger.error(
        "Failed to update note",
        exc_info=e,
        extra={
            "user_id": user_id,
            "note_id": str(note_id),
            "operation": "update",
            "context": additional_context
        }
    )
    raise
```

**Assigned to:** _Unassigned_
**Date Started:** _Not started_

---

### 🔴 LOW-4: Complex Tool Skill Matching Logic
**Status:** 🔴 Not Started
**Effort:** S (30 minutes)
**Impact:** Minor - verbose code

**Location:** `backend/api/services/tool_mapper.py:164-176,183-192`

**Description:**
The same skill set is checked in two places:

```python
if context and tool_config.get("skill") in {
    "fs", "notes", "web-save", # ... 9 items
}:

# Later...
if parameters.get("user_id") and tool_config.get("skill") in {
    "fs", "pdf", "pptx", # ... 9 items
}:
```

**Recommended Solution:**
Define as constants:

```python
SKILLS_REQUIRING_USER_ID = {
    "fs", "pdf", "pptx", "docx", "xlsx",
    "youtube-download", "youtube-transcribe",
    "audio-transcribe", "web-crawler-policy",
    "notes", "web-save"
}

# Then use:
if context and tool_config.get("skill") in SKILLS_REQUIRING_USER_ID:
```

**Assigned to:** _Unassigned_
**Date Started:** _Not started_

---

### 🔴 LOW-5: Unused Parameters
**Status:** 🔴 Not Started
**Effort:** S (15 minutes)
**Impact:** Minor code cleanliness

**Location:** `frontend/src/routes/api/v1/[...path]/+server.ts:7`

**Description:**
The catch-all proxy receives `params` but never uses it:

```typescript
const handler: RequestHandler = async ({ request, params, url, locals, fetch }) => {
  // params is never used, relies on url.pathname instead
```

**Recommended Solution:**
Remove unused parameter or add linter suppression.

**Assigned to:** _Unassigned_
**Date Started:** _Not started_

---

## Deferred Items

Items that have been reviewed and intentionally deferred.

### ⏸️ DEF-1: skill_file_ops_ingestion.py LOC Limit
**Status:** ⏸️ Deferred
**Reason:** File is 689 lines (target 600) but has strong cohesion. All helpers already extracted. Further splitting would reduce code quality by scattering cohesive API.

**Decision Date:** 2026-01-05
**Reviewed by:** Team
**Notes:** The 600-line limit served its purpose by prompting examination. Examination showed file is appropriately sized for its responsibility (complete file system operations API).

---

## Metrics

**Total Active Items:** 22
- **Critical:** 0
- **High:** 4
- **Medium:** 7
- **Low:** 5
- **Deferred:** 1

**Total Estimated Effort:** ~15-20 days
- High: 6-8 days
- Medium: 9-12 days
- Low: 4-5 days

---

## Review Cycle

This backlog should be reviewed:
- **Weekly:** During sprint planning (prioritize items for current sprint)
- **Monthly:** Review deferred items (should any be reconsidered?)
- **Quarterly:** Full review of all items (are priorities still correct?)

**Last Reviewed:** 2026-01-05
**Next Review:** 2026-01-12

---

## Notes

- Items marked 🔴 (Not Started) are candidates for upcoming sprints
- Items marked 🟡 (In Progress) should be completed before starting new ones
- Items marked ⏸️ (Deferred) have been explicitly decided against (for now)
- Keep "Last Updated" date current when making changes
- Delete completed items from this document (git history preserves the record)
- Add notes about implementation decisions for future reference
