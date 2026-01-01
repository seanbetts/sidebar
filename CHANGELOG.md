# Changelog

## Unreleased

- Switched fs skill operations to ingestion-backed storage (list/read/write/delete/move/rename/search).
- Added `path` support for ingested files and folder-aware uploads.
- Removed legacy `file_objects` code paths in favor of ingestion.
- Improved `scripts/migrate.sh` Supabase flow (URL parsing, password prompt, env overrides).
