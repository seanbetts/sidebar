# Refactoring Backlog

**Date Created:** 2026-01-05
**Last Updated:** 2026-01-05 (LOW-1 completed)
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

## Low Priority

Nice-to-have improvements that don't significantly impact functionality.

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

**Total Active Items:** 4
- **Critical:** 0
- **High:** 0
- **Medium:** 0
- **Low:** 4
- **Deferred:** 1

**Total Estimated Effort:** ~2-4 days
- Low: 2-4 days

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
