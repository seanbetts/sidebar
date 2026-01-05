# Refactoring Backlog

**Date Created:** 2026-01-05
**Last Updated:** 2026-01-05 (LOW-2 to LOW-5 completed)
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

**All low-priority items have been resolved.**

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

**Total Active Items:** 0
- **Critical:** 0
- **High:** 0
- **Medium:** 0
- **Low:** 0
- **Deferred:** 1

**Total Estimated Effort:** ~0 days

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
