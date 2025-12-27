# R2 Storage Migration Plan (Replace /workspace)

## Goals
- Move document/file storage from container `/workspace` to Cloudflare R2.
- Preserve current file APIs and skills behavior while enabling multi-device access.
- Prepare for cloud-deployed FastAPI without local filesystem coupling.

## Current Storage Usage (Inventory)
- API file browsing + CRUD uses local paths under `WORKSPACE_BASE`:
  - `backend/api/routers/files.py`
- Workspace enforcement and path jailing:
  - `backend/api/security/path_validator.py`
  - `backend/api/executors/skill_executor.py`
- Profile images stored on the container filesystem:
  - `backend/api/routers/settings.py` (uses `/workspace/profile-images`)
- Skills that read/write local files:
  - `backend/skills/fs/scripts/*` (list/read/write/search/move/etc.)
  - `backend/skills/web-save/scripts/save_url.py` (writes `/workspace/websites`)
  - `backend/skills/youtube-download/scripts/download_video.py`
  - `backend/skills/youtube-transcribe` (Downloads/Transcripts)
  - `backend/skills/web-crawler-policy` (Reports output)
  - `backend/skills/docx` (workspace-based unpack/edit flows)
- Frontend relies on `/api/files/*` endpoints for browsing and file ops.

## Target Architecture
- Introduce a storage abstraction layer with two backends:
  - Local filesystem (dev fallback)
  - Cloudflare R2 (primary)
- Store profile images in R2 (same bucket as documents) and keep DB fields for object keys/URLs.
- Add a metadata store in Postgres for R2 objects:
  - `files` table keyed by `user_id`, `path`, `bucket_key`, `size`, `content_type`,
    `etag`, `created_at`, `updated_at`, `deleted_at`, `category`
  - Enables fast tree listing, rename/move, and search without listing R2 prefixes
- Use R2 object keys organized by user and category:
  - `user_id/documents/...`
  - `user_id/notes/...`
  - `user_id/websites/...`
  - `user_id/downloads/...`
  - `user_id/reports/...`
  - `user_id/transcripts/...`
- Access pattern:
  - API uses R2 credentials (server-side) for read/write.
  - Frontend downloads via signed URLs, or API proxy for small payloads.

## R2 Setup
- Create R2 bucket for workspace storage.
- Create scoped API token with read/write for the bucket.
- Capture S3-compatible endpoint, access key, secret key, and bucket name.
- Add env vars (example names):
  - `R2_ENDPOINT`, `R2_BUCKET`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`

## Migration Steps (Suggested Order)
1) **Storage Abstraction**
   - Add a storage interface (`list`, `get`, `put`, `delete`, `copy`, `move`).
   - Implement LocalFS + R2 backends.
2) **Metadata Table**
   - Add `files` table via Alembic (user-scoped, indexed on `user_id`, `path`).
   - Backfill metadata for existing local files during migration.
3) **API Updates**
   - Update `backend/api/routers/files.py` to use storage service + metadata.
   - Update search to read metadata (and optionally index file content for small files).
4) **Profile Images**
   - Move uploads from `/workspace/profile-images` to R2.
   - Store object keys/URLs in `user_settings.profile_image_path` (or a new field).
4) **Skills Updates**
   - For skills that output files, write to a local temp dir, then upload to R2.
   - For skills that read files, download from R2 to temp before processing.
   - Keep `WORKSPACE_BASE` as a temp staging area only.
5) **Data Migration**
   - Sync `/workspace` contents into R2 using a one-off script.
   - Populate metadata table with paths, sizes, etags, and timestamps.
6) **Cutover**
   - Set storage backend to R2 in config.
   - Keep local filesystem backend available for tests/dev fallback.
7) **Validation**
   - File tree, rename/move, delete, download, and search via UI.
   - Skill outputs appear in expected R2 paths.

## Search Considerations
- Current search scans file contents on disk.
- Options for R2:
  - Metadata-only search (name/path) for now.
  - Add content indexing for small text files into a `file_contents` table.
  - Defer full-text search until file ingestion pipeline is in place.

## Phase 2: Content Indexing (Optional)
- Add `file_contents` table keyed by `file_id` with text content and updated_at.
- Index with PostgreSQL full-text search (tsvector) or trigram for partial matches.
- Update write paths to extract text for small files only (size threshold).
- Add a background job for larger files or heavy parsing.

## Security & Access Control
- Keep R2 bucket private; only API has credentials.
- Use per-user prefixes and DB-scoped metadata to prevent cross-user access.
- Leverage existing `user_id` from request auth to scope all operations.

## Rollback Plan
- Keep local `/workspace` storage intact during migration.
- Maintain a local backup before cutover.
- Flip storage backend back to LocalFS if needed.

## Open Questions
- Do we want to index file contents now or later?
- Should skills be refactored to stream to R2 directly (avoid local temp storage)?
