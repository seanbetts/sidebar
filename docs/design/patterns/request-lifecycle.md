---
title: Request Lifecycle
description: How sideBar executes API requests across native surfaces, including auth refresh, retryability, backoff, cancellation, offline handoff, and diagnostics.
---

## Purpose

Define the standard lifecycle for API work in sideBar across iOS, macOS, widgets, and extensions. This covers how requests are started, retried, cancelled, refreshed for auth, handed off to offline queues, and observed for diagnostics.

This is the app-wide behavioural contract for request execution. Feature code should rely on this policy, not invent its own request behaviour.

## Why this matters

Request behaviour is part of the product experience. Users do not care whether a failure came from `URLSession`, auth refresh, or a background upload. They care whether sideBar feels reliable, predictable, and honest about what is happening.

Without a shared request policy:

- some operations silently retry while others fail immediately
- some requests recover from expired auth while others force the user to retry
- some background operations survive connectivity changes while others do not
- diagnostics become inconsistent and hard to compare across features

## Scope

This document covers:

- native app API requests
- native chat streaming requests
- file upload and download requests
- widget and extension API work
- offline queued writes
- request diagnostics and observability hooks

This document does not define user-facing error surfaces. That belongs in [Error Handling](./error-handling) and [Error Presentation](./error-presentation).

---

## Lifecycle model

Every request in sideBar follows the same high-level lifecycle:

1. **Classify** the request type
2. **Prepare** auth, timeout, cancellation, and diagnostics context
3. **Execute** with the shared transport policy
4. **Recover** through auth refresh, retry, or offline handoff when allowed
5. **Map** the outcome into domain and presentation state
6. **Record** diagnostics for both success and failure

Feature code should not decide these rules ad hoc. The request type determines the allowed recovery paths.

---

## Request classes

| Request class | Examples | Default policy |
|---|---|---|
| **Foreground read** | Load notes tree, fetch settings, refresh task counts | Safe to auto-retry on transient transport failures |
| **Foreground mutation** | Rename note, archive website, update settings | No blind retry by default, must avoid duplicate effects |
| **Streaming** | Chat SSE response stream | Long-lived connection, no hidden reconnect after partial output |
| **Upload / download** | File upload, profile image upload, website download | Progress-aware, cancellable, background-capable where needed |
| **Background refresh** | Widget refresh, cached revalidation, session refresh | Silent retry allowed within a bounded budget |
| **Offline queued write** | Note edit, task mutation, website mutation while offline | Persist locally, retry later with queue backoff policy |

---

## Shared transport contract

All request shapes should share the same transport policy, even when they do not use the same helper API.

That contract includes:

- one auth token source per surface
- one auth refresh policy
- one retryability decision model
- one timeout model
- one cancellation model
- one diagnostics hook set
- one error envelope shape before presentation mapping

Different request helpers may exist for JSON, SSE, multipart upload, or background transfer, but they should all implement the same policy.

---

## Auth refresh

Expired auth should be treated as a transport recovery concern, not as feature-specific logic.

### Rules

- A request that fails with `401` may attempt auth refresh once
- The retry should happen only after the token source has been updated or the refresh operation has explicitly succeeded
- Auth refresh must be coordinated so concurrent failures do not trigger refresh storms
- If auth refresh fails, the original request fails with an auth-classified error
- Feature code must not implement its own token-refresh retry loop
- If the request cannot refresh because no retry credential is available, the auth session must move to `reauthenticationRequired`
- Feature code must not render auth-required list placeholders for hard auth failures; the app-level auth surface owns that user experience

Recoverable stale auth and hard auth expiry are different outcomes:

| Outcome | Meaning | Request-layer response | User experience |
|---|---|---|---|
| `staleRecoverable` | Token or connectivity recovery is still possible | Pause protected server reads, allow automatic recovery | App remains usable with eligible cached data |
| `reauthenticationRequired` | Credentials were rejected or no retry credential exists | Stop protected reads and realtime subscriptions | Full-screen "Sign in again" surface |

Stale recovery is automatic. A feature may observe the degraded state for presentation, but it must not ask the user to fix a recoverable refresh path before the shared auth layer has finished its own recovery attempt.

### Applicability

| Request class | Auth refresh |
|---|---|
| Foreground read | Yes |
| Foreground mutation | Yes, once, if the request is safe to replay |
| Streaming | Yes before connect, not after partial output has started |
| Upload / download | Yes before first byte is sent, not by duplicating an in-flight upload body |
| Background refresh | Yes |
| Offline queued write | Yes when replayed from the queue |

The important distinction is between refreshing before a request starts again and replaying an already-partial side effect. The former is allowed. The latter is not.

---

## Retryability

Retries are only correct when the request can be replayed safely and the user experience remains honest.

### Automatic retry is allowed for

- idempotent reads
- background refresh work
- session refresh and connectivity probes
- queued writes replayed by the offline write queue

### Automatic retry is not allowed for

- user-triggered mutations without replay safety
- uploads that may already have been accepted by the server
- streams that have already emitted partial output
- any operation where a second attempt could duplicate user-visible side effects

### Safe replay conditions for mutations

A foreground mutation may auto-retry only when at least one of these is true:

- the server endpoint is idempotent by definition
- the request includes an operation ID or equivalent dedupe token
- the request has not yet begun sending a body
- the retry is an auth refresh replay that happens before the operation reaches application logic

If those conditions are not met, the failure should surface to the user or be handed to the offline queue.

---

## Backoff

When retry is allowed, use bounded exponential backoff with jitter.

### Standard retry schedule

| Attempt | Delay |
|---|---|
| 1 | immediate or 1s |
| 2 | approx. 2s |
| 3 | approx. 4s |
| 4 | approx. 8s |
| 5 | approx. 16s |

### Rules

- Add jitter so identical failing requests do not retry in lockstep
- Cap the delay rather than growing without bound
- Respect server retry hints when available
- Do not keep retrying indefinitely in the foreground
- If the user has already been shown a failure, do not continue hidden retries behind their back

The offline write queue may use its own persisted retry budget, but it should follow the same exponential shape.

---

## Timeouts

Timeouts should be based on request shape, not feature-by-feature guesswork.

| Request class | Timeout direction |
|---|---|
| Foreground read | Short |
| Foreground mutation | Short to medium |
| Streaming | Long-lived, idle-aware |
| Upload / download | Medium to long, size-aware |
| Background refresh | Bounded by platform execution budget |

### Rules

- Do not leave requests with no timeout strategy
- Do not use the same timeout for SSE, small JSON reads, and multipart upload
- Timeout expiry should map to a standard timeout error category, not a custom per-feature message

---

## Cancellation

Cancellation is a first-class outcome, not a generic failure.

### Rules

- User-initiated cancellation should stop work quickly and cleanly
- Cancellation should not be reported as an error to the user unless the user needs to know that the operation was interrupted
- Cancelled requests should not consume retry budget
- A cancelled stream or upload must release local state and background tasks

### UX contract

- User cancels upload: stop the upload, clean up local temp files, update state to cancelled
- User leaves a screen: foreground reads may cancel silently
- Stream disconnect: end the stream cleanly and only show an error if the stream ended unexpectedly

---

## Offline handoff

sideBar supports optimistic and queued work. Connectivity loss should route operations into the correct lane rather than producing arbitrary failures.

### Rules

- Reads fail normally when offline, with cached data used when available
- User-triggered mutations that support offline mode should enqueue into the write queue
- The queue becomes the owner of retry and backoff once a write is persisted there
- Features that do not support offline mode should fail explicitly and consistently
- Uploads do not silently become queued writes unless the product has explicitly defined that handoff

Offline support is a product decision, not a side effect of transport failure.

---

## Refresh ownership

Background refresh should be coordinated centrally, not reinvented by each screen.

### Rules

- a shared refresh coordinator owns launch refresh, foreground revalidation, reconnect refresh, and pinned-content refresh policy
- individual list and detail views may request data, but they should not each invent their own refresh cadence or offline fallback rules
- when renderable cached content already exists, revalidation should stay silent and must not re-show an initial loading state
- reconnect handling should prioritize replaying queued writes before issuing overlapping refreshes for the same resources
- automatic refresh should merge newer payloads into cache and only notify presentation state when visible data actually changed

This keeps request behavior consistent across notes, tasks, websites, files, and chat browsing while avoiding unnecessary UI churn.

---

## Streaming and upload special cases

### Streaming

- Chat streams are not ordinary reads
- No hidden reconnect after partial assistant output
- Stream failures map into the chat-stream error model, not the generic error surface model
- Tool execution state and partial output must stay truthful if the stream dies

### Uploads

- Upload helpers should share auth, timeout, and error-envelope rules with JSON requests
- Large uploads must be cancellable
- Background-capable uploads should continue through app backgrounding when the product promises that behaviour
- Upload completion and upload polling should not use separate, conflicting error policies

---

## Diagnostics contract

Every request path should emit a common minimum set of diagnostics.

### Required context

- request class
- feature or surface
- operation name
- result: success, failure, cancelled
- retry count
- auth-refresh attempted or not

### Rules

- Success and failure should be observable through the same request pipeline
- Shared request helpers should emit diagnostics automatically
- Feature code may add domain context, but should not replace the shared request diagnostics
- Diagnostics must avoid leaking user content or raw sensitive payloads

See [Error Handling](./error-handling) for logging and capture rules.

---

## Rules summary

1. **All request shapes follow one policy.** JSON, upload, streaming, widgets, and extensions should share the same lifecycle rules even when implemented with different helpers.
2. **Auth refresh is centralized.** Feature code does not implement its own retry-on-401 behaviour.
3. **Retry is opt-in by request class.** Do not auto-retry user mutations, uploads, or streams unless replay safety is explicit.
4. **Use bounded exponential backoff with jitter.** No unbounded loops, no lockstep retries.
5. **Cancellation is not a generic error.** Treat it as its own outcome.
6. **Offline handoff is explicit.** Writes either queue, fail clearly, or continue online, based on product policy.
7. **Uploads and streams are first-class request types.** They do not get weaker standards because they use custom `URLSession` code.
8. **Diagnostics are part of the contract.** Every request path emits comparable request metadata.

---

## Related docs

- [Authentication](./authentication)
- [Wait UX](./wait-ux)
- [Error Handling](./error-handling)
- [Error Presentation](./error-presentation)
