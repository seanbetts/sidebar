---
title: Error Handling
description: How sideBar classifies, logs, captures, maps, and presents errors across native surfaces.
---

## Purpose

Define the app-wide error-handling contract for sideBar. This covers how raw failures become classified errors, how diagnostics are recorded, and how feature code turns those errors into user-facing outcomes.

This is the internal policy layer that sits between request execution and UI presentation.

## Why this matters

Errors are not only UI copy. They are also classification, recovery policy, logging quality, and diagnostic usefulness.

Without a shared error policy:

- backend strings leak straight into the product voice
- different features classify the same failure differently
- logs and Sentry captures become hard to compare
- some failures are actionable while others are opaque

The result is an app that feels inconsistent and is harder to debug.

## Scope

This document covers:

- transport and networking errors
- API response errors
- auth and session failures
- validation and domain errors
- logging and diagnostics capture
- presentation mapping contracts

This document does not define which UI surface to use. That belongs in [Error Presentation](./error-presentation).

---

## Error pipeline

All errors should move through the same pipeline before they reach the UI.

1. **Raw failure**
   `URLError`, HTTP status, backend payload, decoding failure, domain conflict
2. **Classified error**
   transport, auth, validation, conflict, provider overload, capability boundary, unknown
3. **Mapped presentation error**
   short user-safe message, retryability, optional detail, optional diagnostic code
4. **UI surface decision**
   toast, alert, inline text, placeholder, banner, chat error pill

Feature code should not jump from raw error directly to user-visible copy unless the condition is a local validation rule owned entirely by that feature.

---

## Error classes

| Class | Meaning | Typical examples |
|---|---|---|
| **Transport** | Request could not complete at the network layer | offline, timeout, DNS failure, TLS failure |
| **Auth / session** | Credentials missing, expired, or rejected | 401, token expired, session refresh failed |
| **Permission** | User is authenticated but not allowed | 403, gated capability, forbidden action |
| **Validation** | User input or request shape is invalid | invalid URL, malformed OTP, bad provider key |
| **Conflict / stale state** | Client state is out of date relative to the server | write conflict, stale update token |
| **Provider availability** | Upstream AI or dependent service is overloaded or limited | rate limit, provider busy, upstream timeout |
| **Capability boundary** | Operation is not available by design | unsupported feature, not available offline |
| **Unknown** | Failure has not been specifically classified yet | unexpected response, uncategorized backend message |

These classes should be stable across the app. A timeout in Chat and a timeout in Files are different product moments, but they are the same error class.

---

## Backend messages are not product copy

Server-provided messages are diagnostic input, not user-facing copy.

### Rules

- Raw backend text must never be shown directly unless it has been explicitly whitelisted as safe product copy
- Backend messages should map into stable app error classes first
- The product voice stays owned by the client design system, not by incidental backend wording
- Technical detail may be retained for diagnostics and developer-facing drill-down, but not for ordinary toasts or alerts

This is especially important for:

- generic backend exception text
- provider-specific wording
- request IDs and stack-trace-like content
- implementation-detail messages that sound unlike sideBar

---

## Mapping rules

### Transport layer

- `offline` maps to a standard offline message and may also drive `OfflineBanner`
- `timeout` maps to a standard timeout message
- `secure connection` maps to a standard secure-connection message
- `cancelled` remains distinct from failure where the user experience requires that distinction

### HTTP and API layer

- Status codes are not shown directly to users
- Status codes map into stable categories first
- Backend payloads may refine the category, but do not override the product voice

### Domain layer

Domain-owned conditions may use explicit copy when the app already knows the exact user problem:

- invalid URL
- sync queue full
- content not available offline yet
- file too large

These are still part of the shared error catalogue. They should not appear as arbitrary one-off strings spread through view models.

---

## Presentation contract

Error handling and error presentation are separate decisions.

### Error handling owns

- classification
- retryability
- diagnostics detail
- default user-safe message
- whether the error is transient or permanent

### Error presentation owns

- toast vs alert vs inline text vs placeholder vs banner
- timing and dismissal
- contextual layout
- accessibility of the chosen surface

This separation keeps UI surfaces consistent while still allowing the same underlying error class to appear differently in different contexts.

---

## Retryability contract

Every mapped error should answer one question clearly: should the user or system try again?

| Retryability | Meaning |
|---|---|
| **Automatic** | Safe for the request layer to retry |
| **User retryable** | Safe to expose a retry action |
| **Not retryable** | Retrying will not help without a different user action |

Examples:

- timeout: automatic or user-retryable
- provider overloaded: user-retryable
- invalid URL: not retryable until the user edits the input
- auth expired: retryable only after reauth
- conflict: retryable after refresh or explicit conflict resolution

Feature code should not guess this from string content. It should come from the mapped error.

---

## Logging

All error logging should follow a standard structure.

### Required fields

- feature or surface
- operation
- error class
- retryability
- request class when relevant
- underlying domain and code when relevant

### Rules

- Log the classified error, not only the final user message
- Keep logs structured and comparable across features
- Do not log raw user content or sensitive payloads
- A user-facing toast is not a substitute for structured logging

Local `Logger` output is appropriate for development and device diagnostics. It should still follow the shared structure.

---

## Sentry and failure capture

Sentry capture is for actionable failures and debugging context, not for every expected local validation event.

### Capture rules

- Capture unexpected failures, repeated failures, and important workflow failures
- Include sanitized feature and operation context
- Preserve stable classification metadata
- Do not capture sensitive user content, raw prompts, or private file paths

### Do not capture by default

- expected local validation errors
- user-cancelled actions
- product boundaries such as locked plans or offline-only capability limits

Breadcrumbs should describe the user journey leading to a failure. Capture events should preserve enough context to make the issue debuggable.

---

## Shared catalog

sideBar should maintain a shared error catalog for recurring cases.

The catalog should include:

- stable error class
- canonical user-facing copy
- retryability
- default presentation recommendation
- diagnostics metadata expectations

Examples that belong in the shared catalog:

- session expired
- network unavailable
- request timed out
- provider busy
- provider rate limited
- sync queue full
- item unavailable offline
- secure connection failed
- invalid provider key

This prevents the same concept from appearing as five slightly different strings across the app.

---

## Platform and surface notes

### Native app

- Use the shared classifier and mapper
- Feature view models consume mapped errors, not raw transport details

### Chat streaming

- Uses the shared classification rules, but maps into the dedicated chat-stream presentation model
- May retain extra detail and request IDs for the chat error popover

### Widgets and extensions

- May use a narrower user-message catalog because their surfaces are smaller
- Should still classify failures using the same underlying categories

---

## Rules summary

1. **Raw failures do not go straight to the UI.** Classify first, present second.
2. **Backend strings are not product copy.** They are diagnostic input unless explicitly approved.
3. **Use stable app-wide error classes.** Timeout, auth failure, validation failure, conflict, and provider overload should mean the same thing everywhere.
4. **Retryability is part of the mapped error.** Feature code should not infer it from message text.
5. **Log structured error context.** Feature, operation, class, and underlying code should be available in diagnostics.
6. **Sentry capture must include sanitized context.** A capture API that drops context is incomplete.
7. **Keep a shared recurring-error catalog.** Do not let common failures fragment into ad hoc strings.
8. **UI surfaces stay in `error-presentation.md`.** This document defines policy, not layout.

---

## Related docs

- [Request Lifecycle](./request-lifecycle)
- [Error Presentation](./error-presentation)
- [Wait UX](./wait-ux)
- [Authentication](./authentication)
