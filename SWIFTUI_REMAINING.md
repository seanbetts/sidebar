# SwiftUI Remaining Work Plan (Jan 2026)

## Goal
Finish the remaining SwiftUI parity work with a short, focused checklist.

## Remaining Items

1) Phase 11.2 (Markdown editor)
- [ ] Selection/undo parity: keep cursor stable on external updates.
- [ ] Long-note performance: incremental rendering + minimal layout churn.

2) Phase 11.4 (Content creation)
- [ ] Memories CRUD (add/edit/delete) and list/detail parity.

3) Phase 11.5 (Full app testing)
- [ ] Test all editing workflows (notes, files, websites, chat).
- [ ] Test creation/deletion flows across content types.
- [ ] Final polish + bug fixes.

4) Addendum parity gaps
- [ ] Things integration scope (macOS/iOS native API plan + placeholder states).
- [x] Skills settings parity in Settings.
- [x] SSE UI event coverage beyond tokens/tool calls.

## Notes
- Ingestion Center and cancel/pause/resume are deferred unless needed.
- Keep file sizes within limits; prefer service-layer reuse.
