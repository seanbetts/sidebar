# Realtime Handling Plan

## Notes (table: notes)
- INSERT: add note node to tree
- UPDATE: update title/folder/pinned/archived fields
- DELETE or deleted_at: remove node
- Scratchpad note uses special title; update scratchpad cache

## Websites (table: websites)
- INSERT/UPDATE: upsert website summary
- DELETE or deleted_at: remove website

## Ingested Files (table: ingested_files)
- INSERT: trigger list refresh
- UPDATE: update item fields and pin state
- DELETE or deleted_at: remove item

## File Jobs (table: file_processing_jobs)
- UPDATE: update job status and viewer state
- If job row arrives for unknown file, trigger list refresh

## UI Coupling
- Apply realtime changes immediately to view models.
- Schedule a background revalidation to reconcile.
