# iOS Cache Strategy (Initial)

## Goals
- Fast view loads for chat, notes, files, websites.
- Allow read-only browsing when offline.
- Keep cache invalidation simple.

## Initial Cache Targets
- Conversations list (TTL: 15m)
- Note tree + note content (TTL: 15m)
- Websites list + last opened website (TTL: 15m)
- Ingestion list (TTL: 5m)
- Scratchpad content (TTL: 7d)

TODO: Revisit TTLs once native UX flows are implemented (likely longer-lived caches).

## Storage
- In-memory cache for the MVP (fast iteration).
- Add disk cache after Xcode project lands, using a simple key/value store.

## Invalidation
- Realtime events should refresh the local cache.
- Manual refresh triggers a background revalidation.
- On logout, purge cached data.
