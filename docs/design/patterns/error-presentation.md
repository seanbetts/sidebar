---
title: Error Presentation
description: When and how to surface errors to users — which presentation surface to use, when each is appropriate, and the rules that govern error copy.
---

## Purpose

Define when and how sideBar surfaces errors to users — which presentation surface to use, when each is appropriate, and the rules that govern error copy.

## Why this matters

Errors are high-stakes UX moments. The wrong surface creates friction, desensitisation, or missed feedback. An alert that should have been a toast interrupts the user's flow. An inline text that should have been an alert gets missed. Consistent rules make errors feel intentional and give users a reliable mental model for what requires attention.

## Scope

All user-facing error states: operation failures, validation errors, load failures, and persistent connection issues. Does not cover success feedback (see [feedback-and-haptics](./feedback-and-haptics)) or loading states (see [wait-ux](./wait-ux)).

---

## Design rules

### The five presentation surfaces

| Surface | Component | Dismissal | When to use |
|---|---|---|---|
| **Toast** | `ToastCenter` | Auto (2.5s) | Async operation failed; user is unblocked |
| **Alert** | `.alert` | User tap | Error requires acknowledgment before continuing |
| **Inline text** | Red caption `Text` | Clears on correction | Form or field validation error |
| **Placeholder** | `PlaceholderView` | N/A — replaces content | Content area failed to load and is empty |
| **Banner** | `OfflineBanner` | Auto (connection restores) | Persistent connection degradation |

---

### Toast

Use a toast when an async operation in the background failed and the user's current task is unblocked. The error is informational — the user can continue, and the system may recover automatically.

- "Failed to refresh notes"
- "Failed to load archived notes"
- File ingestion failed

Use `ToastCenter.show(message:style:)` with `.error` style. The 2.5s auto-dismiss duration is the default and should not be overridden for errors.

Do not show a toast and an alert for the same error — pick one.

---

### Alert

Use an alert when the error requires the user to acknowledge a blocker or make a decision before continuing. The operation was user-initiated and the failure has direct, visible consequences.

- Login failure
- Website save failed
- Session expired / auth required

Use the system `.alert` modifier. Use `DeleteConfirmationAlert` for all destructive operation confirmations — it wraps `.alert` with consistent wording and button roles.

---

### Inline text

Use inline text when the error refers to a specific field the user is actively editing. Co-locate the error with the field it refers to.

- Invalid email format in login
- Invalid URL when saving a website
- API key validation failure in onboarding
- API key validation failure in Settings
- OTP code invalid

Use `.appFont(.caption)` with `DesignTokens.Colors.error` foreground. Clear the error when the field value changes — do not leave stale validation errors on screen.

---

### Placeholder

Use `PlaceholderView` when a content area or detail view failed to load and has nothing to show. Always include a retry action.

- "Unable to load chat"
- "Unable to load note"
- "Unable to load tasks"

`PlaceholderView` takes `iconName`, `title`, `subtitle`, `actionTitle`, and `action`. The retry action should re-trigger the load. If the content area has stale data from a previous successful load, prefer a toast over a placeholder — leave the stale content in place.

---

### Banner

Use `OfflineBanner` when the device is offline or the server is unreachable. The condition is persistent and affects the whole session, not a single operation.

`OfflineBanner` is already built into `PanelHeader`. Pass the relevant connection state to `PanelHeader` — do not render `OfflineBanner` directly or add a second connection state indicator.

---

### Chat stream errors

Chat stream errors use a dedicated three-part presentation: `ChatErrorPillView` (compact in-thread indicator), `ChatErrorRetryActionView` (retry button), and `ChatErrorPopoverContent` (detail popover on tap). This pattern is specific to streaming AI responses.

For retryable stream errors (provider overloaded, rate limited, timeout, transport failure, empty response): show the pill and retry button in the message thread. For non-retryable errors (auth, context too large, tool exhaustion): show the pill without retry.

`ChatErrorPillView` and its siblings are specific to the chat stream flow — do not reuse them outside `Views/Chat/`.

---

### Error message rules

- When handling a caught `Error` (network, transport, auth), always convert it via `ErrorMapping.message(for:)` — do not pass raw error descriptions to the UI.
- Domain-level conditions the ViewModel checks explicitly (sync queue full, content not available offline, invalid URL format) may use explicit string literals — but follow the same copy rules below.
- Keep messages short: one sentence. No stack traces, no HTTP status codes.
- Describe what went wrong and, where possible, what the user can do. "Failed to save website. Check your connection and try again." not "Error 503".
- Do not expose technical details (request IDs, raw errors) in toasts or alerts. Technical context belongs in the chat error popover detail view only.

---

### Retryability

When an operation fails:

- Content area is empty (load failure): show `PlaceholderView` with a retry action.
- Content area has stale content (refresh failure): show a toast, leave the stale content in place.
- Streaming operation in chat: use the retryable/non-retryable logic in `ChatViewModel+StreamingErrors`.
- Do not implement silent auto-retry without user visibility. If a retry also fails, surface the failure.

---

## Subscription states vs errors

Subscription-related states require careful classification. Some are product boundaries, others are genuine errors.

### Not errors (do not use error surfaces)

| State | Correct surface |
|---|---|
| Free user tries to chat | Subscription prompt in chat input area (see [Subscription](./subscription)) |
| Message cap reached | Inline disabled state with reset time and optional upgrade prompt |
| Plus user taps a flagship skill | Upgrade prompt in skill detail view |
| Free user browses locked skills | Tier badge on skill card, upgrade prompt on tap |

These are expected product boundaries. Using toasts, alerts, red text, or `PlaceholderView` for these states would misrepresent them as failures. Use the upgrade prompt pattern from [Subscription](./subscription).

### Errors (use standard error surfaces)

| State | Correct surface |
|---|---|
| Subscription payment failed | Banner (persistent, like `OfflineBanner`). "There's a problem with your subscription. Update your payment to continue." with an action linking to subscription management. |
| Subscription expired (grace period ended) | Banner. "Your subscription has expired." with a "Resubscribe" action. |
| StoreKit purchase failed mid-checkout | Inline error text in the plan picker or onboarding payment step. |
| Stripe webhook failure (server-side) | Not user-facing unless it results in access loss, in which case treat as subscription expired. |

Payment and subscription failures are real errors that block functionality the user expects to have. Use the standard error surfaces with actionable messages.

---

## Accessibility notes

- `ToastCenter` announces messages via VoiceOver accessibility notifications automatically.
- `OfflineBanner` has an accessibility label and hint — do not suppress them.
- Inline error text must use `DesignTokens.Colors.error` (not `.red`) for correct adaptive dark mode contrast.
- System `.alert` inherits full VoiceOver support automatically.

---

## Rules summary

1. **Match the surface to the severity.** Toast for background failures, alert for blockers, inline text for validation, placeholder for load failures, banner for connection state.
2. **Never show a toast and an alert for the same error.** Pick one.
3. **Use `ToastCenter` for async operation failures.** Inject via `@EnvironmentObject` or pass into the view model.
4. **Use `PlaceholderView` for content areas that fail to load.** Always include a retry action.
5. **Use `DeleteConfirmationAlert` for all destructive confirmations.** Do not write inline `.alert` delete dialogs.
6. **Inline error text belongs next to the field.** Use `.appFont(.caption)` with `DesignTokens.Colors.error`. Clear on correction.
7. **`OfflineBanner` is built into `PanelHeader`.** Do not render it directly or add a second connection state indicator.
8. **Caught `Error` values go through `ErrorMapping.message(for:)`.** Never pass `.localizedDescription` to the UI.
9. **`ChatErrorPillView` is chat-only.** Do not reuse it outside `Views/Chat/`.

---

## Related docs

- [Subscription](./subscription) — subscription boundary patterns (not errors)
- [Feedback and Haptics](./feedback-and-haptics) — success states, haptic feedback
- [Wait UX](./wait-ux) — loading and in-progress states
- [Components Overview](../components/overview) — ToastCenter, OfflineBanner, PlaceholderView, DeleteConfirmationAlert
