# Changelog

## Unreleased

- Switched fs skill operations to ingestion-backed storage (list/read/write/delete/move/rename/search).
- Added `path` support for ingested files and folder-aware uploads.
- Added `backend/scripts/migrate_file_objects_to_ingestion.py` to migrate legacy `file_objects`.
- Improved `scripts/migrate.sh` Supabase flow (URL parsing, password prompt, env overrides).
