# Refactoring Backlog

**Date Created:** 2026-01-05
**Last Updated:** 2026-01-05
**Status:** Active

This document tracks refactoring opportunities identified during code reviews. Items are prioritized and tracked to completion.

---

## Table of Contents

- [Critical Priority](#critical-priority)
- [High Priority](#high-priority)
- [Medium Priority](#medium-priority)
- [Low Priority](#low-priority)
- [Completed Items](#completed-items)
- [Deferred Items](#deferred-items)

---

## How to Use This Document

- **Priority levels**: Critical → High → Medium → Low
- **Status**: 🔴 Not Started | 🟡 In Progress | 🟢 Completed | ⏸️ Deferred
- **Effort**: S (< 1 day) | M (1-3 days) | L (3-5 days) | XL (> 1 week)
- **Impact**: What breaks or degrades if not fixed

When starting work on an item:
1. Change status to 🟡 In Progress
2. Add your name and date
3. Create a branch if needed
4. Update "Last Updated" date at top
5. Move to "Completed Items" when done

---

## Critical Priority

Issues that will cause runtime errors, data loss, or severe performance degradation.

### 🔴 CRIT-1: Missing Import for WebsiteProcessingService
**Status:** 🔴 Not Started
**Effort:** S (5 minutes)
**Impact:** Runtime error when quick-save endpoints are called

**Location:** `backend/api/routers/websites.py:112,127`

**Description:**
The file uses `WebsiteProcessingService.create_job()` at lines 112 and 127 but doesn't import the class.

**Error:**
```python
# Lines 112, 127 - WebsiteProcessingService not imported
job = WebsiteProcessingService.create_job(db, user_id, normalized_url)
# NameError: name 'WebsiteProcessingService' is not defined
```

**Fix:**
```python
# Add to imports section
from api.services.website_processing_service import WebsiteProcessingService
```

**Files to Modify:**
- `backend/api/routers/websites.py`

**Tests:**
- Call `/api/v1/websites/quick-save` endpoint
- Verify no import errors

**Assigned to:** _Unassigned_
**Date Started:** _Not started_

---

## High Priority

Issues that cause bugs, performance problems, or significant maintainability concerns.

### 🔴 HIGH-1: Duplicated Pinned Order Logic
**Status:** 🔴 Not Started
**Effort:** M (2 days)
**Impact:** Bug fixes need applying twice, N+1 query performance issue

**Location:**
- `backend/api/services/notes_service.py:318-334`
- `backend/api/services/websites_service.py:310-326`

**Description:**
The `update_pinned()` method contains nearly identical logic for calculating `pinned_order` in both services. Both implementations:
1. Fetch **all** user entities from database
2. Iterate in Python to find max `pinned_order`
3. Set new order to `max + 1`

**Current Pattern:**
```python
# Repeated in both services
if pinned:
    if metadata.get("pinned_order") is None:
        max_order = -1
        for existing in (
            db.query(Note)  # or Website
            .filter(Note.user_id == user_id, Note.deleted_at.is_(None))
            .all()
        ):
            existing_meta = existing.metadata_ or {}
            if not existing_meta.get("pinned"):
                continue
            try:
                order_value = int(existing_meta.get("pinned_order"))
            except (TypeError, ValueError):
                order_value = -1
            max_order = max(max_order, order_value)
        metadata["pinned_order"] = max_order + 1
```

**Issues:**
- Fetches all user records even if only 1 is pinned
- Python iteration instead of SQL aggregation
- Duplicate code → bug fixes need applying twice
- Risk of implementation divergence

**Recommended Solution:**

**Option 1: Shared utility with SQL aggregation**
```python
# backend/api/utils/metadata_helpers.py
from sqlalchemy import func, cast, Integer
from sqlalchemy.dialects.postgresql import JSONB

def get_max_pinned_order(
    db: Session,
    model_class,
    user_id: str
) -> int:
    """
    Get max pinned_order value using SQL aggregation.

    Uses PostgreSQL JSONB operators to query max value directly
    instead of fetching all records and iterating in Python.
    """
    # Query: SELECT MAX(CAST(metadata_->>'pinned_order' AS INTEGER))
    # FROM {table}
    # WHERE user_id = :user_id
    #   AND deleted_at IS NULL
    #   AND metadata_->>'pinned' = 'true'
    result = (
        db.query(
            func.max(
                cast(
                    model_class.metadata_["pinned_order"].astext,
                    Integer
                )
            )
        )
        .filter(
            model_class.user_id == user_id,
            model_class.deleted_at.is_(None),
            model_class.metadata_["pinned"].astext == "true"
        )
        .scalar()
    )
    return result or 0

# Then in services:
from api.utils.metadata_helpers import get_max_pinned_order

def update_pinned(self, db: Session, user_id: str, note_id: uuid.UUID, pinned: bool):
    # ...
    if pinned and metadata.get("pinned_order") is None:
        metadata["pinned_order"] = get_max_pinned_order(db, Note, user_id) + 1
    # ...
```

**Option 2: Base service class with shared method**
```python
# backend/api/services/base_service.py
class MetadataServiceMixin:
    """Mixin for services handling metadata with pinned_order."""

    @staticmethod
    def get_next_pinned_order(db: Session, model_class, user_id: str) -> int:
        # Same SQL aggregation as Option 1
        pass

# Then:
class NotesService(MetadataServiceMixin):
    # Inherit the method
```

**Files to Create:**
- `backend/api/utils/metadata_helpers.py` (Option 1)
- OR `backend/api/services/base_service.py` (Option 2)

**Files to Modify:**
- `backend/api/services/notes_service.py`
- `backend/api/services/websites_service.py`

**Tests Required:**
- Unit tests for `get_max_pinned_order()` with various scenarios:
  - No pinned items (should return 0)
  - Multiple pinned items (should return max)
  - Invalid pinned_order values (should handle gracefully)
- Integration tests for `update_pinned()` in both services
- Performance test: measure query time with 1000+ records

**Migration Notes:**
- Ensure existing `pinned_order` values are compatible with new logic
- May need data migration if any invalid values exist

**Assigned to:** _Unassigned_
**Date Started:** _Not started_

---

### 🔴 HIGH-2: Performance - Multiple Queries on Every Chat Message
**Status:** 🔴 Not Started
**Effort:** M (2-3 days)
**Impact:** Latency on every chat message, database load

**Location:** `backend/api/services/prompt_context_service.py:243-276`

**Description:**
The `_get_recent_activity()` method executes **4 separate sequential queries** on every chat request:

```python
# All executed synchronously
notes = db.query(Note).filter(...).all()
websites = db.query(Website).filter(...).all()
conversations = db.query(Conversation).filter(...).all()
files = db.query(IngestedFile).filter(...).all()
```

Then iterates through all results to build response dictionaries.

**Performance Impact:**
- 4 database round-trips on every chat message
- Blocks chat response stream from starting
- No caching → repeated queries for same user within seconds
- Scales poorly as user data grows

**Recommended Solutions:**

**Short-term (Quick Win):**
```python
# Add simple in-memory cache with TTL
from functools import lru_cache
from datetime import datetime, timedelta

class PromptContextService:
    _activity_cache: dict[str, tuple[datetime, dict]] = {}
    CACHE_TTL = timedelta(minutes=5)

    @classmethod
    def _get_recent_activity(cls, db: Session, user_id: str) -> dict:
        # Check cache
        if user_id in cls._activity_cache:
            cached_at, cached_data = cls._activity_cache[user_id]
            if datetime.utcnow() - cached_at < cls.CACHE_TTL:
                return cached_data

        # Fetch fresh data
        data = cls._fetch_activity_from_db(db, user_id)

        # Update cache
        cls._activity_cache[user_id] = (datetime.utcnow(), data)

        return data
```

**Medium-term (Better Performance):**
1. Add composite indexes on frequently queried columns
2. Use `load_only()` to fetch only needed columns
3. Consider Redis cache for multi-instance deployments

**Long-term (Best Performance):**
1. Denormalize recent activity into `user_settings` table
2. Update via background job or trigger
3. Single query for all recent activity

**Database Indexes to Add:**
```python
# In models
Index('idx_notes_user_last_opened', 'user_id', 'last_opened_at'),
Index('idx_notes_user_deleted_opened', 'user_id', 'deleted_at', 'last_opened_at'),
Index('idx_websites_user_last_opened', 'user_id', 'last_opened_at'),
Index('idx_websites_user_deleted_opened', 'user_id', 'deleted_at', 'last_opened_at'),
Index('idx_ingested_files_user_last_opened', 'user_id', 'last_opened_at'),
Index('idx_conversations_user_last_opened', 'user_id', 'last_opened_at'),
```

**Files to Modify:**
- `backend/api/services/prompt_context_service.py`
- `backend/api/models/note.py`, `website.py`, `file_ingestion.py`, `conversation.py` (add indexes)
- Migration file to add indexes

**Tests Required:**
- Cache hit/miss behavior
- Cache TTL expiry
- Concurrent access to cache
- Performance benchmarks (before/after)

**Metrics to Track:**
- Average query time before/after
- Cache hit rate
- Chat message latency P50, P95, P99

**Assigned to:** _Unassigned_
**Date Started:** _Not started_

---

### 🔴 HIGH-3: Inconsistent Exception Hierarchy
**Status:** 🔴 Not Started
**Effort:** S (1 day)
**Impact:** Cannot catch all "not found" errors uniformly, missing error details

**Location:**
- `backend/api/services/notes_service.py:20` (custom exception)
- `backend/api/services/websites_service.py:16` (custom exception)
- `backend/api/exceptions.py:81-92` (proper base class exists)

**Description:**
Services define local exception classes instead of using the centralized exception hierarchy:

```python
# In notes_service.py:20
class NoteNotFoundError(Exception):
    """Raised when a note is not found."""

# In websites_service.py:16
class WebsiteNotFoundError(Exception):
    """Raised when a website is not found."""
```

But `exceptions.py` already has a proper hierarchy:

```python
# In exceptions.py
class NotFoundError(APIError):
    def __init__(self, resource: str, identifier: str):
        super().__init__(
            status_code=404,
            error_code="NOT_FOUND",
            message=f"{resource} not found: {identifier}",
            details={"resource": resource, "identifier": identifier}
        )
```

**Issues:**
- Cannot catch all "not found" errors with single except clause
- Missing structured error details (status codes, error codes)
- Inconsistent error responses to frontend
- Duplicate exception definitions

**Recommended Solution:**

```python
# Remove from services:
# class NoteNotFoundError(Exception): ...
# class WebsiteNotFoundError(Exception): ...

# Use centralized exceptions instead:
from api.exceptions import NotFoundError

# In notes_service.py
if not note:
    raise NotFoundError("Note", str(note_id))

# In websites_service.py
if not website:
    raise NotFoundError("Website", str(website_id))
```

**Files to Modify:**
- `backend/api/services/notes_service.py` (remove exception, update raises)
- `backend/api/services/websites_service.py` (remove exception, update raises)
- Any code catching `NoteNotFoundError` or `WebsiteNotFoundError`

**Files to Search:**
```bash
# Find all references to old exceptions
grep -r "NoteNotFoundError" backend/
grep -r "WebsiteNotFoundError" backend/
```

**Tests to Update:**
- Any tests catching the old exception types
- Verify error response format matches expected structure

**Migration Notes:**
- This is a breaking change for any code catching specific exception types
- Error messages will change slightly (format from NotFoundError template)
- Error responses will include structured details

**Assigned to:** _Unassigned_
**Date Started:** _Not started_

---

### 🔴 HIGH-4: Silent Error in Title Generation
**Status:** 🔴 Not Started
**Effort:** S (30 minutes)
**Impact:** Failures invisible, difficult to debug production issues

**Location:** `backend/api/routers/chat.py:416-428`

**Description:**
The `generate_title` endpoint catches all exceptions but doesn't log them before returning a fallback:

```python
except Exception as e:
    # Fallback to first message snippet
    fallback_title = user_msg[:50] + ("..." if len(user_msg) > 50 else "")
    return {"title": fallback_title, "fallback": True}
    # 'e' is never logged!
```

**Issues:**
- Silent failures → no visibility into title generation problems
- Cannot monitor error rates or types
- Hard to debug if Gemini API has issues
- Users don't know service is degraded

**Recommended Solution:**

```python
except Exception as e:
    # Log the actual error with context
    logger.warning(
        "Title generation failed, using fallback",
        exc_info=e,
        extra={
            "conversation_id": str(conversation_uuid),
            "user_id": user_id,
            "message_length": len(user_msg),
            "error_type": type(e).__name__
        }
    )

    # Then return fallback
    fallback_title = user_msg[:50] + ("..." if len(user_msg) > 50 else "")
    return {"title": fallback_title, "fallback": True}
```

**Files to Modify:**
- `backend/api/routers/chat.py`

**Tests:**
- Mock title service to raise exceptions
- Verify error is logged with proper context
- Verify fallback still works

**Monitoring:**
- Add metrics for title generation success/failure rates
- Alert if failure rate > 10%

**Assigned to:** _Unassigned_
**Date Started:** _Not started_

---

## Medium Priority

Issues that impact code quality, consistency, or maintainability but don't cause immediate problems.

### 🔴 MED-1: Print Statements in Production Code
**Status:** 🔴 Not Started
**Effort:** S (30 minutes)
**Impact:** Debugging statements pollute stdout, not structured logs

**Location:** `backend/api/services/claude_streaming.py:356,362`

**Description:**
Debug print statements instead of proper logging:

```python
# Line 356
if current_round >= max_rounds:
    print(f"Warning: Hit max tool rounds ({max_rounds})", flush=True)

# Line 362
print(f"Chat streaming error: {error_details}", flush=True)
```

**Issues:**
- Output goes to stdout instead of logs
- Cannot be filtered, disabled, or routed
- No structured context
- Harder to monitor in production

**Recommended Solution:**

```python
import logging
logger = logging.getLogger(__name__)

# Replace line 356
if current_round >= max_rounds:
    logger.warning(
        "Hit max tool rounds limit",
        extra={
            "max_rounds": max_rounds,
            "current_round": current_round,
            "messages_count": len(messages)
        }
    )

# Replace line 362
logger.error(
    "Chat streaming error",
    exc_info=e,
    extra={
        "error_details": error_details,
        "conversation_id": context.get("conversation_id")
    }
)
```

**Files to Modify:**
- `backend/api/services/claude_streaming.py`

**Tests:**
- Verify logging output in tests
- Check log levels are appropriate

**Assigned to:** _Unassigned_
**Date Started:** _Not started_

---

### 🔴 MED-2: Search Query Duplication
**Status:** 🔴 Not Started
**Effort:** M (1 day)
**Impact:** Cannot change search behavior globally, missed optimization opportunities

**Location:**
- `backend/api/services/conversation_service.py:220-222`
- `backend/api/services/websites_service.py:581-583`
- `backend/api/services/notes_workspace_service.py:55-56`

**Description:**
Search implementations duplicate the same `ilike` pattern:

```python
# Repeated in 3 services
or_(
    Model.title.ilike(f"%{query}%"),
    Model.content.ilike(f"%{query}%"),
)
```

**Issues:**
- Cannot easily add features like fuzzy search
- Missing opportunity for consistent ranking
- Duplicate SQL logic
- Hard to add search enhancements globally

**Recommended Solution:**

```python
# backend/api/utils/search.py
from sqlalchemy import or_
from typing import Type, List

def build_text_search_filter(
    model_class: Type,
    query: str,
    fields: List[str],
    case_sensitive: bool = False
) -> any:
    """
    Build a SQLAlchemy filter for text search across multiple fields.

    Args:
        model_class: The SQLAlchemy model to search
        query: Search query string
        fields: List of field names to search across
        case_sensitive: Whether to perform case-sensitive search

    Returns:
        SQLAlchemy filter expression

    Example:
        >>> filter = build_text_search_filter(Note, "python", ["title", "content"])
        >>> notes = db.query(Note).filter(filter).all()
    """
    search_term = f"%{query}%"

    if case_sensitive:
        return or_(*[
            getattr(model_class, field).like(search_term)
            for field in fields
        ])
    else:
        return or_(*[
            getattr(model_class, field).ilike(search_term)
            for field in fields
        ])

# Usage in services:
from api.utils.search import build_text_search_filter

def search_notes(db: Session, user_id: str, query: str):
    search_filter = build_text_search_filter(Note, query, ["title", "content"])
    return db.query(Note).filter(
        Note.user_id == user_id,
        search_filter
    ).all()
```

**Future Enhancements:**
- Add full-text search using PostgreSQL `to_tsvector`
- Add search result ranking
- Support phrase search, wildcard patterns
- Add search highlighting

**Files to Create:**
- `backend/api/utils/search.py`

**Files to Modify:**
- `backend/api/services/conversation_service.py`
- `backend/api/services/websites_service.py`
- `backend/api/services/notes_workspace_service.py`

**Tests Required:**
- Unit tests for `build_text_search_filter()`
- Integration tests for search in each service
- Verify case sensitivity works
- Test with special characters

**Assigned to:** _Unassigned_
**Date Started:** _Not started_

---

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

### 🔴 MED-5: Missing Database Indexes
**Status:** 🔴 Not Started
**Effort:** S (1 day including migration)
**Impact:** Slower queries as data grows, full table scans

**Location:** Various models queried by `last_opened_at`

**Description:**
Recent activity queries filter on `last_opened_at >= start_of_day` but likely missing composite indexes combining `user_id + last_opened_at`.

**Current Queries:**
```python
db.query(Note).filter(
    Note.user_id == user_id,
    Note.deleted_at.is_(None),
    Note.last_opened_at >= start_of_day
).all()
```

**Without Index:** Full table scan or index on `user_id` only
**With Index:** Direct index scan on composite key

**Recommended Solution:**

```python
# In backend/api/models/note.py
__table_args__ = (
    Index('idx_notes_user_last_opened', 'user_id', 'last_opened_at'),
    Index('idx_notes_user_deleted_opened', 'user_id', 'deleted_at', 'last_opened_at'),
)

# Similar for other models:
# backend/api/models/website.py
# backend/api/models/file_ingestion.py
# backend/api/models/conversation.py
```

**Migration:**
```python
# alembic migration
def upgrade():
    # Notes
    op.create_index(
        'idx_notes_user_last_opened',
        'notes',
        ['user_id', 'last_opened_at']
    )
    op.create_index(
        'idx_notes_user_deleted_opened',
        'notes',
        ['user_id', 'deleted_at', 'last_opened_at']
    )

    # Websites
    op.create_index(
        'idx_websites_user_last_opened',
        'websites',
        ['user_id', 'last_opened_at']
    )
    # ... etc
```

**Files to Modify:**
- `backend/api/models/note.py`
- `backend/api/models/website.py`
- `backend/api/models/file_ingestion.py`
- `backend/api/models/conversation.py`
- New Alembic migration

**Testing:**
- Verify indexes created successfully
- Use `EXPLAIN ANALYZE` to confirm index usage
- Benchmark query performance before/after

**Performance Impact:**
- Expected improvement: 10-100x faster for users with 100+ records

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

## Completed Items

_None yet - items will be moved here when completed_

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

**Total Items:** 23
- **Critical:** 1
- **High:** 4
- **Medium:** 7
- **Low:** 5
- **Completed:** 0
- **Deferred:** 1

**Total Estimated Effort:** ~15-20 days
- Critical: 5 minutes
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
- Move completed items to "Completed Items" section for historical record
- Add notes about implementation decisions for future reference
