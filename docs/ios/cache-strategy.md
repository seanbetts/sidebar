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

## Suggested TTL Adjustments (Native UX)
- Conversations list: 30m (frequent list access, low change rate)
- Note tree: 30m; note content: 2h (reading-heavy flows)
- Websites list: 30m; website detail: 2h
- Ingestion list: 5-10m (processing updates matter)
- Scratchpad: 7d (always cache)

TODO: Confirm TTLs after initial native flows and realtime behavior.

## Storage
- In-memory cache for the MVP (fast iteration).
- Add disk cache after Xcode project lands, using a simple key/value store.

## Invalidation
- Realtime events should refresh the local cache.
- Manual refresh triggers a background revalidation.
- On logout, purge cached data.
