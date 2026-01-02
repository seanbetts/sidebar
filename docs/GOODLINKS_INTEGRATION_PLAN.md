# GoodLinks Integration Plan (Deferred)

## Goal

Sync links saved in GoodLinks into the app so they can be rendered as markdown documents (and shared with AI agents).

**Status**: Deferred until the Things integration and multi-bridge hosting are stable.

---

## Notes (for later)

### Why GoodLinks is deferred
- Current priority is Things (read + write).
- Bridge hosting/selection needs to be proven across multiple Macs first.
- GoodLinks can follow the same macOS bridge pattern later.

### Proposed Architecture (when revisited)
- macOS host bridge executes a Shortcuts export.
- FastAPI normalizes JSON → markdown.
- Optional GoodLinks save endpoint via URL scheme.

### Suggested Bridge Endpoints
```
GET /goodlinks/{scope}     # unread | starred | all | tag
POST /goodlinks/save
```

### Canonical Markdown (example)
```
# GoodLinks: Unread

- [ ] Example article title
  - url: https://example.com
  - tags: ai, reading
  - starred: true
  - summary: Optional summary
```
