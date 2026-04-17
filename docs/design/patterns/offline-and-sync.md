---
title: Offline and Sync
description: How sideBar handles local-first reads, optimistic writes, queued sync, unavailable-offline detail states, archives, and multi-device convergence.
---

## Purpose

Define one shared contract for offline behavior and cross-device sync across `chat`, `notes`, `tasks`, `websites`, and `files`.

This doc sits between [wait-ux](./wait-ux), [request-lifecycle](./request-lifecycle), [error-presentation](./error-presentation), and the Apple implementation design. It explains what the product promises, which states users should see, and how those states differ between rows, detail panes, and global sync UI.

## Core rules

1. **Reads are local-first.** If a list or detail payload exists on-device, render it immediately.
2. **Offline-capable writes are optimistic-first.** Apply the local mutation before the server confirms it.
3. **Queued replay is the default recovery path.** When writes cannot be sent immediately, persist them and replay later.
4. **Server unreachable counts as offline behavior.** Users should not see a different model just because the device has network but the backend is unavailable.
5. **Selected detail content never falls back to a generic welcome screen.** Missing cached content is a known unavailable state.
6. **Global sync state and item state are separate.** Use the header pill for queue health. Use row or detail states for item-specific availability or failure.
7. **Multi-device sync converges through the server.** Each device keeps its own local state and queue.

## Product scope

The local-first contract applies to:

- `notes`
- `tasks`
- `websites`
- `files`
- `chat` conversation browsing and management

The one explicit online-only action is:

- sending a new chat message

## Shared read model

Every supported surface follows the same read policy:

- list screens load local snapshots first
- detail screens load local snapshots first
- background refresh runs when network and server state allow it
- if cached content exists, keep showing it while refresh happens
- if cached content does not exist, show an explicit unavailable-offline or load-failed state

### Refresh behavior

The shared read model includes explicit refresh rules so each surface does not invent its own launch or reconnect logic.

Rules:

- cold launch may schedule a silent background refresh for already-cached sections without blocking first render
- warm foreground should revalidate stale visible content opportunistically, not reset the UI to an initial loading state
- reconnect should trigger queue replay first, then a bounded background refresh for affected caches
- pinned content belongs in the background refresh set regardless of count
- background refresh updates cached data in place, it does not clear caches and rebuild them from scratch
- background refresh should not disturb current list selection, scroll position, or visible detail state unless the data actually changed
- archives stay out of the automatic launch refresh path unless the user is actively viewing archive content

This keeps the UI stable while still allowing the cache to converge with newer server state from another device.

### Detail availability states

Every selected detail surface must resolve into one of:

- `available`
- `loading`
- `unavailableOffline`
- `loadFailed`

`unavailableOffline` means the user selected a real item, but this device does not have the needed content cached yet.

Examples:

- a note selected offline that was never opened on this device
- a website selected offline that was never cached locally
- a file row visible locally, but its viewable content was never cached on this device
- a chat conversation selected offline that has no cached transcript on this device

## Shared write model

Every offline-capable mutation follows the same write policy:

- apply the user-visible change locally first
- persist a durable queued mutation
- replay automatically when writes are allowed again
- keep failed writes visible and retryable

This includes:

- create
- rename
- pin and unpin
- archive and unarchive
- move
- reorder
- delete
- content edits such as note body changes and task notes

### Temporary local identity

Offline-created items need stable local IDs until the server acknowledges them.

Rules:

- create a local ID immediately
- allow later queued mutations to target that local ID
- remap local ID to server ID once the create succeeds
- preserve selection, queued child mutations, and cached detail state through the remap

## Conflict policy

When a queued mutation conflicts with newer server state, local wins by default.

The product rule is:

- resolve automatically in favour of the latest local intent
- do not pause the queue for manual conflict resolution
- keep failed writes visible only for real failures, not ordinary version conflicts

## Archive policy

Archived `notes` and `websites` use a hybrid offline model.

Rules:

- archive and unarchive are normal optimistic queued mutations
- archived items already cached on the device remain available offline
- archive lists may render from the local archived subset already on-device
- the app does not proactively mirror the entire archive to every device
- archived items never cached on the current device show `unavailableOffline` when selected offline

This keeps archive behavior consistent with the local-first contract without forcing a large full-archive mirror into the local database.

## Multi-device behavior

Each device owns:

- its own cache
- its own optimistic local state
- its own queued mutations

The server remains the convergence point.

This means:

- if you edit a note on iPhone while offline, the iPhone shows that local change immediately
- the iPad does not see that change until the iPhone reconnects and syncs
- once the server accepts the change, the iPad converges through refresh or realtime
- a later launch or reconnect refresh on the iPad should merge newer server fields into its local cache without wiping older cached content that still has no replacement payload

Cross-device sync should feel fast, but not magical. Offline work is local until the originating device reconnects.

## Status surfaces

### Header pill

Use the existing sync status pill for global queue health:

- pending writes
- syncing in progress
- failed queued writes with retry or cancel actions

Do not invent a second global sync indicator.

### Row-level status

Use compact inline status only when the user benefits from seeing item-specific state. Reuse existing patterns where possible.

Examples:

- pending website row status such as `Queued`, `Reading...`, `Retrying`, `Failed`
- file ingestion status such as `Uploading file...`, `Processing file...`, `Ready`
- compact pending or failed indicators on notes or tasks when useful

### Detail-level status

Use the detail pane for:

- `loading`
- `unavailableOffline`
- `loadFailed`

Do not use the detail pane to show a generic empty welcome screen after the user has selected a real item.

## Surface-specific rules

### Chat

- conversation lists and cached conversations are readable offline
- conversation browsing is local-first
- sending a new message is disabled while offline

### Notes

- tree, note content, and note metadata are local-first
- note and folder CRUD is optimistic and queued
- archived notes follow the hybrid archive policy

### Tasks

- task CRUD, project CRUD, and group CRUD follow the same optimistic queued model
- task completion and edits apply locally first

### Websites

- saved pages are local-first once cached on-device
- save, rename, pin, archive, and delete are optimistic and queued
- archived websites follow the hybrid archive policy

### Files

- file metadata is local-first
- file CRUD is optimistic and queued
- actual file content must be cached on-device for true offline viewing

## Rules summary

1. **Render local content immediately when available.**
2. **Queue supported writes instead of failing them when offline.**
3. **Treat server unreachable as offline behavior.**
4. **Use explicit `unavailableOffline` detail states.**
5. **Use the existing header pill for global sync state.**
6. **Keep row-level state compact and contextual.**
7. **Archive and unarchive behave like any other optimistic queued mutation.**
8. **Offline changes remain local to that device until it reconnects and syncs.**

## Related docs

- [Wait UX](./wait-ux)
- [Request Lifecycle](./request-lifecycle)
- [Error Presentation](./error-presentation)
- [Error Handling](./error-handling)
- [Authentication](./authentication)
- [Implementation Gaps](../implementation-gaps)
