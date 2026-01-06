# Transcript UX Enhancements Plan

## Goal
Improve YouTube transcript UX with status pill, toasts, queued state, and background polling.

## Scope
- Website header: add transcript status pill with colored dot.
- Toasts: completion/failure notifications with retry on failure.
- Button state: show “Queued” and prevent duplicate submissions.
- Background polling: use stored job id to refresh status.

## Plan
1. Review current website header UI and metadata flow to determine where transcript status can be surfaced.
2. Backend: expose transcript job status + file_id from website metadata; ensure ingestion worker updates metadata for queued/processing/ready/failed.
3. Frontend: render status pill, update button state for queued/processing, add polling keyed by file_id, trigger toast on completion/failure.
4. Tests: update backend tests for metadata/status changes; add frontend tests where feasible.

## Completion Criteria
- Status pill appears with correct color (red/amber/green) and state.
- Button disables/relabels when queued/processing.
- Toast appears on completion; failure toast includes retry action.
- Polling updates state without keeping the website detail view open.
