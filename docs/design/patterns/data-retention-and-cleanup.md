---
title: Data Retention And Cleanup
description: How sideBar reclaims backend storage for soft-deleted content, operational exhaust, and deleted-user data without breaking product behavior.
---

## Purpose

Define the app-wide backend lifecycle policy for reclaiming storage from deleted or obsolete data.

This document covers how sideBar should retain, degrade, and purge backend data across content tables, operational tables, and deleted-user cleanup. It defines the target behavioural contract. Feature code should rely on this policy, not invent per-feature cleanup rules.

## Why this matters

Soft delete is the correct default for product safety, undo semantics, and offline sync. It is not sufficient as a long-term storage strategy.

Without a shared retention and cleanup policy:

- soft-deleted rows accumulate indefinitely
- large payload tables continue to grow even when content is no longer user-visible
- indexes bloat with rows that no longer participate in active product behaviour
- workers and idempotency tables retain operational exhaust longer than needed
- deleted-user cleanup becomes incomplete or inconsistent across tables and storage backends

The result is a backend that is harder to operate, more expensive to store, and riskier to evolve.

## Scope

This document covers:

- soft-deleted user content
- tombstone degradation for heavyweight content
- hard-delete retention windows
- operational table cleanup
- deleted-user immediate purge
- minimum cleanup observability

This document does not define the implementation rollout, migration order, or runbook procedures. Those belong in engineering planning and operations documentation.

---

## Lifecycle model

Every cleanup candidate in sideBar should move through one of two lifecycle modes.

### Mode 1: Retention cleanup

Used for ordinary product deletes such as deleting a note, website, file, task, project, or group.

This mode has up to three states:

1. **Active row**
   The row participates in normal product behaviour and has `deleted_at IS NULL`.
2. **Soft-deleted row**
   The row is no longer active, but the full payload is still retained for a bounded restore window.
3. **Tombstone or purged row**
   Heavyweight payload has been removed, or the row has been hard-deleted after the sync-safe retention window expires.

### Mode 2: Deleted-user cleanup

Used when a user account itself is deleted.

This is a terminal lifecycle event. It bypasses ordinary soft-delete retention and should immediately purge all account-scoped data, associated operational records, and remaining storage-backed artifacts.

Feature-level retention windows do not apply once the account is deleted.

---

## Ownership model

Cleanup is backend-owned lifecycle infrastructure, not route-level behaviour.

### User-facing services own

- writing `deleted_at`
- clearing feature state needed at delete time, such as pinned state
- preserving existing conflict and sync semantics at the moment of delete

### Cleanup infrastructure owns

- retention policy evaluation
- tombstone degradation rules
- hard-delete execution
- deleted-user cascade purge
- cleanup metrics and audit logging

The backend should expose one centralized cleanup service area for these responsibilities. Feature services should not each define their own background retention jobs or account-purge logic.

---

## Default retention classes

Retention should be concrete by default so behaviour is predictable and operationally measurable.

| Data class | Full soft-delete window | Total retention window | Final action |
|---|---:|---:|---|
| Notes | 7 days | 90 days | Tombstone after 7 days, hard delete after 90 days |
| Websites | 7 days | 60 days | Tombstone after 7 days, hard delete after 60 days |
| Ingested files metadata | 30 days | 30 days | Hard delete after 30 days |
| Tasks | 60 days | 60 days | Hard delete after 60 days |
| Task projects | 60 days | 60 days | Hard delete after 60 days |
| Task groups | 60 days | 60 days | Hard delete after 60 days |
| User AI provider keys | 7 days | 7 days | Hard delete after 7 days |
| Operational job and idempotency tables | none | 7 to 14 days | Hard delete on table-specific policy |

### Rationale

- **Notes** and **websites** retain the heaviest payloads and should shed storage earliest while still preserving sync-safe tombstones.
- **Ingested files** already remove derivative storage at delete time, so the remaining database row is metadata rather than the primary storage burden.
- **Tasks**, **task projects**, and **task groups** are smaller rows, but still need bounded retention for offline reconciliation.
- **Provider keys** should not linger beyond a short safety window because they are sensitive and not sync-critical.
- **Operational tables** are execution exhaust, not durable product content.

---

## Sync-safe retention

sideBar currently relies on deleted rows remaining observable to sync clients for a bounded period after deletion.

During that sync-safe window, clients should still be able to fetch an updated row and learn that the item was deleted by observing `deleted_at`.

Cleanup must not remove or degrade a row so aggressively that sync can no longer determine:

- which record was deleted
- when it changed
- that the record is deleted rather than merely missing

### Required tombstone fields

Where a table uses tombstone degradation, the degraded row should preserve at least:

- stable record ID
- `user_id`
- `updated_at`
- `deleted_at`
- the minimum lightweight metadata required for client reconciliation or conflict handling

### Restore semantics

Restore is only guaranteed during the full soft-delete window.

Once a row has been degraded to tombstone form, the product no longer guarantees full restoration of original content. Tombstones exist to preserve sync semantics until the hard-delete cutoff, not to preserve indefinite undo.

### Deleted-user exception

Deleted-user cleanup is the explicit exception to sync retention. Once an account is deleted, immediate purge takes precedence over offline reconciliation for that account.

---

## Tombstone degradation

Tombstone degradation should only be used where it provides meaningful storage reduction.

### Heavyweight tables

These tables should support degradation after the full soft-delete window ends:

- `notes`
- `websites`

For these tables, cleanup may remove heavyweight payload fields after 7 days while preserving sync-critical metadata until the total retention window expires.

### Lightweight tables

These tables should not require an intermediate tombstone stage:

- `ingested_files`
- `tasks`
- `task_projects`
- `task_groups`
- `user_ai_provider_keys`

For these tables, ordinary soft-delete retention may be followed directly by hard delete once the retention cutoff is reached.

### Design rule

Tombstone degradation is a storage optimisation, not a second product-visible archive state. Feature code should continue to reason about rows as either active or deleted.

---

## Deleted-user immediate purge

Deleting a user account should trigger immediate removal of all account-scoped data.

### Policy

When user deletion is committed, the backend should purge:

- primary product content rows owned by that user
- child and dependent records
- provider-key material
- operational rows associated with that user
- remaining storage-backed artifacts associated with that user

### Design rule

Deleted-user cleanup must run through one account-scoped purge path. It should not depend on waiting for ordinary retention workers to notice already-deleted rows, and it should not be implemented as unrelated per-table cleanup logic spread across the codebase.

This path should be idempotent so it can be retried safely if any table or storage backend fails partway through purge.

---

## Operational table cleanup

Operational tables should follow short retention windows and should never accumulate indefinitely.

Examples include:

- job status tables
- queue-processing records
- worker heartbeat or lease state
- sync idempotency logs

### Policy

- Keep only the minimum history needed for debugging and recovery
- Use table-specific retention windows between 7 and 14 days
- Delete in bounded batches
- Prefer hard delete rather than soft delete for operational exhaust

This policy is intentionally stricter than user-content retention because these rows exist to support system operation, not user-facing restore behaviour.

---

## Execution rules

Cleanup should be safe, bounded, and restartable.

### Required execution properties

- **Idempotent**
  Re-running cleanup against the same rows should not corrupt state or produce duplicate side effects.
- **Batched**
  Cleanup should operate in bounded chunks to avoid long transactions and avoid lock amplification.
- **Deterministic**
  Candidate selection should use stable predicates such as retention cutoff timestamps and explicit table-specific conditions.
- **Ordered**
  Cleanup should process related data in an order that avoids orphaned records and dangling storage references.
- **Observable**
  Every cleanup path should emit enough signal to determine whether it is running, succeeding, and keeping up with backlog.

### Storage-backed artifacts

When a table references storage objects, cleanup should remove storage artifacts before or alongside hard delete so the database row is not the only thing reclaimed.

---

## Observability minimums

This pattern requires a small, stable observability surface so cleanup behaviour can be trusted in production.

### Required signals

- rows pruned, by table and action type
- rows degraded to tombstone form, by table
- rows hard-deleted, by table
- deleted-user purge executions and outcomes
- last successful cleanup run timestamp
- cleanup lag, defined as oldest row past retention that has not yet been processed

### Recommended signals

- table-level row-count trend for soft-deleted content
- approximate table-size trend for high-volume tables
- cleanup failure count by table and failure class

### Purpose

The goal is not to turn this pattern into a full operational runbook. The goal is to guarantee that retention policy is measurable enough to detect:

- cleanup stopped running
- cleanup is failing repeatedly
- backlog is growing faster than it is reclaimed
- a supposedly reclaimed table continues to grow unchecked

---

## Data-class rules

### Notes

- Soft delete remains the user-facing delete behaviour
- Full row is restorable for 7 days
- After 7 days, heavyweight note payload may be stripped while preserving tombstone metadata
- Hard delete occurs at 90 days

### Websites

- Soft delete remains the user-facing delete behaviour
- Full row is restorable for 7 days
- After 7 days, heavyweight website content may be stripped while preserving tombstone metadata
- Hard delete occurs at 60 days

### Ingested files

- Delete-time cleanup should continue removing derivative storage and derivative rows
- Metadata row may remain soft-deleted for 30 days
- Hard delete occurs at 30 days

### Tasks, task projects, and task groups

- Soft delete remains the user-facing delete behaviour
- No separate tombstone degradation stage is required
- Hard delete occurs at 60 days

### User AI provider keys

- Soft delete is only a short safety window
- Hard delete occurs at 7 days

### Deleted users

- Immediate purge overrides all ordinary retention windows
- No tombstone retention is required after account deletion

---

## Index and query implications

Retention policy and query policy should stay aligned.

Most active product queries exclude deleted rows. As cleanup is introduced, the backend should prefer index strategies that keep active-row access paths efficient even when tombstones exist temporarily.

The design goal is:

- active product reads pay as little cost as possible for retained tombstones
- retained tombstones remain queryable for sync only as long as the policy requires
- long-lived deleted rows do not dominate the same indexes used for active content

This document does not prescribe exact indexes. It does require cleanup-aware indexing as part of implementation.

---

## Non-goals

This pattern does not define:

- the exact migration sequence to reach this target state
- the worker topology or deployment process used to execute cleanup
- the full operations runbook for retention failures
- product-facing copy for delete confirmation or account deletion UX

Those decisions should follow this pattern, not replace it.
