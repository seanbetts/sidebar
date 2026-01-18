# File Upload + Ingestion UX (iOS/macOS)

## Goal
Implement native file upload + YouTube ingestion with async progress tracking and a cleaner UI than the web sidebar queue.

## Scope
- Files panel header: add separate YouTube button next to + upload.
- Async upload manager with native progress updates and local optimistic items.
- Ingestion Center popover/sheet + header status chip (Option 1 + 2).
- YouTube ingestion endpoint integration (`/ingestion/youtube`).
- Viewer shows processing state while file ingest completes.

## Plan
1) UI: add header controls and status chip
- [x] Add YouTube button next to `+` in Files panel header.
- [x] Add a compact status chip in the content header when uploads/processing are active.
- [x] Normalize stage labels shown in the chip (Queued/Preparing/Transcribing/Finalizing).

2) Ingestion Center
- [ ] Create a small panel (popover on macOS, sheet/popover on iOS) listing active uploads/processing.
- [ ] Show filename, stage text, progress bar; enable cancel/pause/resume if available.

3) Upload pipeline
- [x] Build `IngestionUploadManager` using `URLSessionUploadTask` with progress callbacks.
- [x] Create local temporary ingestion items in `IngestionStore` and update progress live.
- [x] Replace local items with real ingestion meta on success; handle failures gracefully.
- [ ] Add cancel/pause/resume support if backend supports it.

4) YouTube ingestion
- [x] Add `ingestYoutube(url:)` to `IngestionAPI` and wire into the YouTube button flow.
- [x] Use a simple alert with a text field for the URL.
- [x] Add processing placeholder (“YouTube Video”) that updates to the real title once ready.

5) Viewer handling
- [x] If selected file is still processing, show “Processing…” in the main workspace.
- [x] Auto-open uploaded items when ready (only if user is in Files; otherwise prompt to open).

## Notes
- Keep uploads async/non-blocking so users can continue using the app.
- Prefer background URLSession on iOS to continue uploads in background.
- Reuse ingestion job stages for progress messaging.
