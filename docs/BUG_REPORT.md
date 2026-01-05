# Bug Report

**Date:** 2026-01-05
**Status:** Resolved
**Priority Bugs:** 0

This document tracks confirmed bugs discovered during comprehensive code review. Unlike the refactoring backlog, these are actual defects that cause incorrect behavior, runtime errors, or data loss.

---

## Critical Severity

Bugs that cause data loss, corruption, or system crashes.

### ✅ BUG-001: Missing Database Transaction in File Deletion
**Severity:** Critical
**Category:** Data Corruption Risk
**Location:** `backend/api/services/files_workspace_service.py:319-333`
**Status:** Resolved (2026-01-05)

**Description:**
The `delete` method performs multiple operations (delete storage objects, delete derivatives, mark file as deleted) without proper transaction boundaries. If any step fails partway through, the system ends up in an inconsistent state.

**Current Code:**
```python
# Line 319-333
derivatives = (
    db.query(FileDerivative)
    .filter(FileDerivative.file_id == record.id)
    .all()
)
for item in derivatives:
    storage_backend.delete_object(item.storage_key)  # External operation - can fail
db.query(FileDerivative).filter(FileDerivative.file_id == record.id).delete()
record.deleted_at = datetime.now(timezone.utc)
db.commit()  # Single commit at the end
```

**Trigger:**
Delete a file while the storage backend is temporarily unavailable, or if storage deletion fails.

**Impact:**
- Storage objects deleted but database records remain (orphaned database entries)
- OR database records deleted but storage objects remain (orphaned storage, cost implications)
- User sees file as deleted but storage costs continue
- OR user sees file exists but cannot access it

**Recommended Fix:**

**Option 1: Soft delete first, clean storage in background**
```python
def delete(self, user_id: str, file_id: str) -> dict:
    """Mark file as deleted immediately, clean storage in background."""
    # ... find record ...

    # Soft delete first (atomic, fast)
    record.deleted_at = datetime.now(timezone.utc)
    db.commit()

    # Queue storage cleanup for background job
    # This way, user sees immediate feedback and storage cleanup happens eventually
    try:
        derivatives = db.query(FileDerivative).filter(...).all()
        for item in derivatives:
            try:
                storage_backend.delete_object(item.storage_key)
            except Exception as e:
                logger.warning(f"Failed to delete storage object {item.storage_key}: {e}")
                # Continue with other deletions

        # Delete derivative records after storage cleanup succeeds
        db.query(FileDerivative).filter(FileDerivative.file_id == record.id).delete()
        db.commit()
    except Exception as e:
        logger.error(f"Storage cleanup failed for file {file_id}: {e}")
        # File is marked as deleted in DB, storage cleanup can be retried later
```

**Option 2: Roll back on storage failure**
```python
def delete(self, user_id: str, file_id: str) -> dict:
    """Delete file with rollback on storage failure."""
    # ... find record ...

    try:
        # Get derivatives before deletion
        derivatives = db.query(FileDerivative).filter(...).all()
        storage_keys = [d.storage_key for d in derivatives]

        # Delete from storage first (external operation)
        failed_deletions = []
        for key in storage_keys:
            try:
                storage_backend.delete_object(key)
            except Exception as e:
                failed_deletions.append((key, str(e)))

        if failed_deletions:
            raise StorageError(f"Failed to delete {len(failed_deletions)} storage objects")

        # Only if storage deletion succeeds, update database
        db.query(FileDerivative).filter(FileDerivative.file_id == record.id).delete()
        record.deleted_at = datetime.now(timezone.utc)
        db.commit()

    except Exception as e:
        db.rollback()
        raise
```

**Files to Modify:**
- `backend/api/services/files_workspace_service.py`

**Tests Required:**
- Test deletion when storage backend fails
- Test deletion when database fails after storage deletion
- Test concurrent deletions of same file

**Priority:** Fix immediately - data corruption risk

---

### ✅ BUG-002: Race Condition in Pinned Order Assignment
**Severity:** Critical
**Category:** Race Condition
**Location:** `backend/api/services/file_ingestion_service.py:193-204`
**Status:** Resolved (2026-01-05)

**Description:**
When pinning an item, the code queries for max pinned_order, then increments it. Two concurrent requests can get the same max value, resulting in duplicate pinned_order values.

**Current Code:**
```python
if pinned:
    if record.pinned_order is None:
        max_order = (
            db.query(func.max(IngestedFile.pinned_order))
            .filter(
                IngestedFile.user_id == user_id,
                IngestedFile.deleted_at.is_(None),
            )
            .scalar()
        )
        record.pinned_order = (max_order if max_order is not None else -1) + 1
```

**Trigger:**
Two users (or same user in two tabs) pinning different items simultaneously.

**Impact:**
- Multiple items with same pinned_order value
- Inconsistent UI ordering (items jump around)
- Pinned items may disappear or reorder unexpectedly
- Users cannot reliably organize their pinned items

**Recommended Fix:**

**Option 1: Use SELECT FOR UPDATE (row-level locking)**
```python
if pinned:
    if record.pinned_order is None:
        # Lock the rows with highest pinned_order to prevent concurrent updates
        max_order_record = (
            db.query(IngestedFile)
            .filter(
                IngestedFile.user_id == user_id,
                IngestedFile.deleted_at.is_(None),
                IngestedFile.pinned_order.isnot(None),
            )
            .order_by(IngestedFile.pinned_order.desc())
            .with_for_update()  # Row-level lock
            .first()
        )
        max_order = max_order_record.pinned_order if max_order_record else -1
        record.pinned_order = max_order + 1
```

**Option 2: Use database sequence**
```python
# In migration, create a sequence per user
# For now, use a simpler approach with retry on conflict

def get_next_pinned_order(db: Session, user_id: str) -> int:
    """Get next pinned order with retry on conflict."""
    max_retries = 3
    for attempt in range(max_retries):
        max_order = (
            db.query(func.max(IngestedFile.pinned_order))
            .filter(
                IngestedFile.user_id == user_id,
                IngestedFile.deleted_at.is_(None),
            )
            .scalar()
        )
        next_order = (max_order if max_order is not None else -1) + 1

        # Check if this order was taken by another transaction
        conflict = (
            db.query(IngestedFile)
            .filter(
                IngestedFile.user_id == user_id,
                IngestedFile.pinned_order == next_order,
                IngestedFile.deleted_at.is_(None),
            )
            .first()
        )

        if not conflict:
            return next_order

        # Retry with fresh query
        time.sleep(0.01 * (attempt + 1))  # Exponential backoff

    raise RuntimeError("Failed to assign pinned order after retries")
```

**Also affects:**
- `backend/api/services/notes_service.py:318-334` (same issue)
- `backend/api/services/websites_service.py:310-326` (same issue)

**Files to Modify:**
- `backend/api/services/file_ingestion_service.py`
- `backend/api/services/notes_service.py`
- `backend/api/services/websites_service.py`

**Tests Required:**
- Concurrent pinning test (simulate 10 simultaneous pin operations)
- Verify all items get unique pinned_order values
- Test with database under load

**Priority:** Fix in next sprint - affects UX, not data loss but very annoying

---

### ✅ BUG-003: Missing JSON Parse Error Handling
**Severity:** Critical
**Category:** Error Handling Gap
**Location:**
- `backend/api/routers/weather.py:71`
- `backend/api/routers/places.py:37`
**Status:** Resolved (2026-01-05)

**Description:**
JSON parsing from external APIs (Open-Meteo, Google Places) is done without try/except blocks. If the API returns malformed JSON, the application crashes with `JSONDecodeError`.

**Current Code:**
```python
# weather.py:71
return json.loads(data.decode("utf-8"))

# places.py:37
return json.loads(data.decode("utf-8"))
```

**Trigger:**
External API returns invalid JSON due to:
- Network corruption
- API server error (returns HTML error page instead of JSON)
- Partial response (connection interrupted mid-transmission)
- Character encoding issues

**Impact:**
- Unhandled `JSONDecodeError` exception
- HTTP 500 error to user
- Weather widget breaks entire chat interface
- Location autocomplete fails silently

**Recommended Fix:**

```python
# weather.py
try:
    return json.loads(data.decode("utf-8"))
except json.JSONDecodeError as e:
    logger.error(
        "Failed to parse weather API response",
        exc_info=e,
        extra={
            "response_preview": data[:500],  # First 500 bytes for debugging
            "lat": lat,
            "lon": lon
        }
    )
    raise ExternalServiceError(
        "Weather service returned invalid data",
        service="Open-Meteo"
    )

# places.py
try:
    return json.loads(data.decode("utf-8"))
except json.JSONDecodeError as e:
    logger.error(
        "Failed to parse places API response",
        exc_info=e,
        extra={
            "response_preview": data[:500],
            "query": query
        }
    )
    raise ExternalServiceError(
        "Places service returned invalid data",
        service="Google Places"
    )
```

**Files to Modify:**
- `backend/api/routers/weather.py`
- `backend/api/routers/places.py`
- `backend/api/exceptions.py` (add `ExternalServiceError` if not exists)

**Tests Required:**
- Mock external API to return invalid JSON
- Verify proper error response
- Verify error is logged with context

**Priority:** Fix immediately - can crash user-facing features

---

## High Severity

Bugs that cause incorrect behavior or user-facing errors.

### ✅ BUG-004: Missing Database Rollback on Streaming Error
**Severity:** High
**Category:** Data Corruption Risk
**Location:** `backend/api/services/claude_streaming.py:358-363`
**Status:** Resolved (2026-01-05)

**Description:**
The catch-all exception handler in the streaming service doesn't perform database rollback. If a database session is active and an exception occurs during tool execution, the session remains in a dirty state with uncommitted changes.

**Current Code:**
```python
except Exception as e:
    import traceback
    error_details = f"{type(e).__name__}: {str(e)}\n{traceback.format_exc()}"
    print(f"Chat streaming error: {error_details}", flush=True)
    yield {"type": "error", "error": str(e)}
```

**Trigger:**
- Tool execution fails mid-stream
- Network error to Claude API
- Database constraint violation during tool execution
- Any unhandled exception

**Impact:**
- Database session left in dirty state
- Subsequent operations in same session may see uncommitted data
- Potential for partial data writes
- Transaction isolation violations

**Recommended Fix:**

```python
except Exception as e:
    import traceback
    error_details = f"{type(e).__name__}: {str(e)}\n{traceback.format_exc()}"

    # Log the error properly instead of print
    logger.error(
        "Chat streaming error",
        exc_info=e,
        extra={
            "context": context,
            "messages_count": len(messages)
        }
    )

    # Rollback any uncommitted database changes
    if context and "db" in context:
        try:
            context["db"].rollback()
        except Exception as rollback_error:
            logger.error(f"Failed to rollback database session: {rollback_error}")

    yield {"type": "error", "error": str(e)}
```

**Files to Modify:**
- `backend/api/services/claude_streaming.py`

**Tests Required:**
- Simulate tool execution failure
- Verify database is rolled back
- Verify subsequent operations work correctly

**Priority:** Fix in next sprint - risk of data corruption

---

### ✅ BUG-005: Memory Leak in Tool State Timers
**Severity:** High
**Category:** Memory Leak
**Location:** `frontend/src/lib/stores/chat/toolState.ts:14-25`
**Status:** Resolved (2026-01-05)

**Description:**
The `toolClearTimeout` and `toolUpdateTimeout` timers are stored at module level but never cleaned up when components unmount or the store is destroyed. This leads to memory leaks and potential callback execution on stale state.

**Current Code:**
```typescript
export function createToolStateHandlers(update: UpdateFn, getState: GetStateFn) {
  let toolClearTimeout: ReturnType<typeof setTimeout> | null = null;
  let toolUpdateTimeout: ReturnType<typeof setTimeout> | null = null;

  const clearToolTimers = () => {
    if (toolClearTimeout) {
      clearTimeout(toolClearTimeout);
      toolClearTimeout = null;
    }
    if (toolUpdateTimeout) {
      clearTimeout(toolUpdateTimeout);
      toolUpdateTimeout = null;
    }
  };

  // clearToolTimers is defined but never called on cleanup
  // ...
}
```

**Trigger:**
- User navigates away from chat while tools are executing
- User closes chat window
- Component unmounts during tool execution

**Impact:**
- Memory leak (timers not garbage collected)
- Callbacks execute on unmounted components
- State updates to destroyed stores
- Potential crashes or UI corruption

**Recommended Fix:**

```typescript
export function createToolStateHandlers(update: UpdateFn, getState: GetStateFn) {
  let toolClearTimeout: ReturnType<typeof setTimeout> | null = null;
  let toolUpdateTimeout: ReturnType<typeof setTimeout> | null = null;

  const clearToolTimers = () => {
    if (toolClearTimeout) {
      clearTimeout(toolClearTimeout);
      toolClearTimeout = null;
    }
    if (toolUpdateTimeout) {
      clearTimeout(toolUpdateTimeout);
      toolUpdateTimeout = null;
    }
  };

  // ... existing functions ...

  // Return cleanup function
  return {
    handleToolCallStart,
    handleToolCallComplete,
    handleToolUpdateProgress,
    clearToolTimers,

    // Add cleanup function
    cleanup: () => {
      clearToolTimers();
      // Clear any other resources
    }
  };
}

// In the store:
export function createChatStore() {
  const { subscribe, set, update } = writable<ChatState>(initialState);
  const toolHandlers = createToolStateHandlers(update, () => get(chatStore));

  // ... store methods ...

  // Add cleanup on store destroy
  const cleanup = () => {
    toolHandlers.cleanup();
  };

  return {
    subscribe,
    // ... methods ...
    cleanup  // Export cleanup for consumers
  };
}
```

**Usage in Components:**
```svelte
<script lang="ts">
import { chatStore } from '$lib/stores/chat';
import { onDestroy } from 'svelte';

onDestroy(() => {
  chatStore.cleanup();
});
</script>
```

**Files to Modify:**
- `frontend/src/lib/stores/chat/toolState.ts`
- `frontend/src/lib/stores/chat.ts` (add cleanup method)
- Components that use chatStore (add onDestroy)

**Tests Required:**
- Mount/unmount component rapidly
- Verify timers are cleared
- Check for memory leaks with browser dev tools

**Priority:** Fix in next sprint - memory leak

---

## Summary

**Total Bugs Found:** 5

**By Severity:**
- Critical: 0 (resolved)
- High: 0 (resolved)

**By Category:**
- Data Corruption Risk: 3
- Race Condition: 1
- Memory Leak: 1

**Immediate Action Required:** None

**Next Sprint:** None

**Total Estimated Effort:** 0 hours (all fixes completed)

---

## Code Quality Assessment

Overall, the codebase is **well-written** with good error handling patterns. The bugs found are edge cases and race conditions rather than fundamental design flaws. Key observations:

**Strengths:**
- Proper use of SQLAlchemy (no SQL injection risks)
- Good separation of concerns
- Most JSONB updates correctly use `flag_modified()`
- Type hints used consistently
- Input validation generally good

**Areas for Improvement:**
- Transaction boundaries around multi-step operations
- Concurrency handling for shared resources
- External API error handling
- Resource cleanup in frontend

**False Positives Investigated:**
During the bug hunt, several potential issues were investigated but found to be safe:
- Cache eviction using `pop(key, None)` - safe with default value
- Date calculations with `startOfDay()` - correct normalization
- Empty array checks - proper guards in place

The bugs identified are real issues that should be addressed, but they don't indicate systemic problems with code quality.

---

**Last Updated:** 2026-01-05
**Review Status:** Initial bug hunt complete
