# Skills Storage Alignment Plan

## Progress Tracker

- [ ] Add ingestion helper APIs + backward-compatible frontmatter schema
- [x] Deprecate/remove docx/pdf/pptx/xlsx skills and update docs/tool registry
- [x] Update audio-transcribe + youtube-download
- [ ] Update youtube-transcribe
- [ ] Update web-crawler-policy (single ingested file per run)
- [ ] Update SKILL.md documentation
- [ ] Verify UI reads `ai/ai.md` consistently and ignores website transcript records

## Goals

- Ensure all file-producing skills store outputs in the ingestion-backed `{user_id}/files/{file_id}/` structure.
- Standardize `ai/ai.md` generation with frontmatter for AI context, backward-compatible with current consumers.
- Preserve derivatives for UI previews in `derivatives/`.
- Update skill outputs and docs to reference `file_id` and derivative metadata instead of raw R2 paths.
- Deprecate and remove `docx`, `pdf`, `pptx`, and `xlsx` skills from the codebase.

## Current Storage Model (Target)

- Storage key root: `{user_id}/files/{file_id}/`
- `ai/ai.md`: frontmatter + markdown extracted or generated for AI context.
- `derivatives/`: processed artifacts for UI preview (pdf/image/audio/video/etc).
- UI grouping: derived from file type, not physical folder paths.

## Required Platform Changes

### 1) Add Explicit Ingestion Helpers

Create a helper that can:

- Create an `IngestedFile` record with metadata.
- Write one or more derivative objects (binary files) into `derivatives/`.
- Write or update `ai/ai.md` into `ai/`.
- Return a single payload with `file_id`, `ai_path`, and `derivative_paths`.

Suggested API surface (new functions in `backend/api/services/skill_file_ops_ingestion.py`):

- `create_ingested_file(user_id, filename, mime, size, source_url=None, source_metadata=None) -> IngestedFile`
- `write_ai_markdown(user_id, file_id, content, *, frontmatter: dict) -> storage_key`
- `write_derivative(user_id, file_id, local_path, *, kind, content_type=None) -> storage_key`
- `finalize_ingested_file(user_id, file_id, *, primary_derivative_kind=None) -> dict`

Notes:
- `write_ai_markdown` should build a consistent frontmatter schema (see "Frontmatter Schema").
- `write_derivative` should map `kind` to `derivatives/{kind}.{ext}` or `derivatives/{kind}`.
- `finalize_ingested_file` should update ingestion tables with derivative info and processing status.

### 2) Frontmatter Schema for ai/ai.md (Backward-Compatible)

Use a consistent schema across skills while keeping existing keys that current consumers rely on:

```
---
file_id: <uuid>
source_filename: <string>
source_mime: <string>
created_at: <iso8601>
sha256: <string|null>
source_url: <string|null>
source_type: <string|null> # e.g. "youtube", "audio-transcribe", "web-crawler"
ingestion:
  skill: <string>
  model: <string|null>
  language: <string|null>
  duration_seconds: <number|null>
  size_bytes: <number|null>
derivatives:
  ai_md: true
  text_original: true
derivative_items:
  - kind: <string>
    path: <storage-key>
    content_type: <string|null>
---
```

Keep this ASCII-only. Add optional fields as needed.

### 3) Update Skill Output Payloads

All file-producing skills should return:

- `file_id`
- `ai_path` (storage key for `ai/ai.md`)
- `derivatives` (list of `{kind, path, content_type}`)

Deprecate returning `r2_path` as the primary identifier.

## Skill-by-Skill Plan

### audio-transcribe

Current:
- Writes a transcript file and uploads via `upload_file`.
- Optionally writes a note.

Target:
- Create one ingested file per transcript.
- Store transcript in `ai/ai.md` with frontmatter.
- Optionally store the original audio as a derivative (if requested).
- Optional NotesService save remains a secondary side effect.

Changes:
- Replace `save_transcript_to_r2` with ingestion helper calls.
- Add `source_type: "audio-transcribe"` and `model`, `language`, `duration_seconds`.
- If input audio is local only, store derivative via `write_derivative` as `audio_original`.
- Update return payload to include `file_id`, `ai_path`, `derivatives`.

Files:
- `backend/skills/audio-transcribe/scripts/transcribe_audio.py`

### youtube-download

Current:
- Uploads MP4/MP3 to a path like `files/videos/...` via `upload_file`.

Target:
- Create one ingested file per download.
- Store video/audio as `derivatives/video_original` or `derivatives/audio_original`.
- Write `ai/ai.md` with metadata (title, URL, channel, duration).

Changes:
- Use ingestion helper to create file_id and store derivatives.
- Set `source_type: "youtube-download"` and `source_url` to the YouTube URL.
- Include duration and format in frontmatter.
- Return `file_id`, `ai_path`, `derivatives`.

Files:
- `backend/skills/youtube-download/scripts/download_video.py`

### youtube-transcribe

Current:
- Downloads audio, transcribes, uploads transcript to a path, optional note.

Target:
- Use a single ingested file record for both audio derivative and transcript AI markdown.
- If audio is kept, store as `derivatives/audio_original`.
- Transcript stored in `ai/ai.md`.

Changes:
- Create ingested file at the start of the workflow.
- Write transcript using `write_ai_markdown`.
- Write audio derivative only if `--keep-audio`.
- Include `source_url`, `title`, `model`, `language`.
- Update return payload.

Files:
- `backend/skills/youtube-transcribe/scripts/transcribe_youtube.py`

### web-crawler-policy

Current:
- Produces multiple files and uploads to `Reports/{domain}`.

Target:
- Create a single ingested file per scan run.
- Write a synthesized `ai/ai.md` summary report.
- Store raw artifacts under `derivatives/`:
  - `robots_txt`, `llms_txt`, `analysis_csv`, `analysis_json`, `report_md`

Changes:
- Add a summary builder for `ai/ai.md` (short paragraph + key counts).
- Write derivatives via ingestion helper.
- Return `file_id` and derivative list.

Files:
- `backend/skills/web-crawler-policy/scripts/analyze_policies.py`

### fs

Current:
- Writes text files via ingestion.

Target:
- Keep as-is, but ensure that text writes become the `ai/ai.md` derivative for that file where appropriate.

Changes:
- Review `write_text` to ensure it creates or updates `ai/ai.md` and a `text_original` derivative when the file is text.
- If already handled in ingestion pipeline, document it in SKILL.md.

Files:
- `backend/skills/fs/scripts/write.py`
- `backend/api/services/skill_file_ops_ingestion.py`

### notes / web-save

Current:
- Stored in Postgres tables.

Target:
- Keep DB storage.
- If you want “file-like” previews in UI for notes/websites, add optional ingestion export later (not required for alignment).

Changes:
- Update SKILL.md docs to reflect DB-only behavior.

Files:
- `backend/skills/notes/SKILL.md`
- `backend/skills/web-save/SKILL.md`

### docx / pdf / pptx / xlsx (Deprecate)

Decision:
- Remove these skills from the codebase as part of this alignment.
- Update any docs and tool registries to reflect removal.

Files:
- `backend/skills/docx/`
- `backend/skills/pdf/`
- `backend/skills/pptx/`
- `backend/skills/xlsx/`

## UI/UX Alignment

- Ensure UI uses file type classification on derivatives, not on paths.
- Ensure “AI view” always reads `ai/ai.md` for context.
- Any UI listing should be based on ingestion records, not raw storage keys.

## Migration Considerations

- Leave existing skill outputs intact; new outputs use `file_id` structure.
- Optionally add a background migrator for existing R2 paths to the new structure.
- For now, the UI can handle both styles if necessary.

## Suggested Rollout

1) Add ingestion helper APIs + backward-compatible frontmatter schema.
2) Deprecate/remove docx/pdf/pptx/xlsx skills and update docs/tool registry.
3) Update audio-transcribe + youtube-download (lowest dependency).
4) Update youtube-transcribe to reuse new helpers.
5) Update web-crawler-policy outputs (single ingested file per run).
6) Update SKILL.md documentation.
7) Verify UI reads `ai/ai.md` consistently and ignores website transcript records.
