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
- Add YouTube button next to `+` in Files panel header.
- Add a compact status chip in the content header when uploads/processing are active.

2) Ingestion Center
- Create a small panel (popover on macOS, sheet/popover on iOS) listing active uploads/processing.
- Show filename, stage text, progress bar; enable cancel/pause/resume if available.

3) Upload pipeline
- Build `IngestionUploadManager` using `URLSessionUploadTask` with progress callbacks.
- Create local temporary ingestion items in `IngestionStore` and update progress live.
- Replace local items with real ingestion meta on success; handle failures gracefully.

4) YouTube ingestion
- Add `ingestYoutube(url:)` to `IngestionAPI` and wire into the YouTube button flow.
- Use a simple alert with a text field for the URL.

5) Viewer handling
- If selected file is still processing, show “Processing…” in the main workspace.
- Auto-open uploaded items when ready.

## Notes
- Keep uploads async/non-blocking so users can continue using the app.
- Prefer background URLSession on iOS to continue uploads in background.
- Reuse ingestion job stages for progress messaging.
