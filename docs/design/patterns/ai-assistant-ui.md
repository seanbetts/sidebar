---
title: AI Assistant UI
description: Visual and interaction patterns for assistant-driven and AI-supported moments across sideBar.
---

| Field | Value |
|---|---|
| Status | draft |
| Owner | both |
| Outputs | this doc |
| Dependencies | [navigation](./navigation), [handoffs](./handoffs), [wait-ux](./wait-ux), [feedback-and-haptics](./feedback-and-haptics) |

## Purpose

Define how assistant-driven moments look and behave across sideBar. The assistant is not a separate layer pasted on top of the app — its surfaces must feel like a natural extension of the product. This doc covers the chat conversation, generation states, tool call disclosure, error and retry behaviour, workspace surfaces, and assistant handoffs into product features.

Voice and copy guidelines for assistant interactions are covered in [voice-and-content](../voice-and-content).

---

## Design principles

**The assistant is always identified.** Every assistant message carries the assistant's configured name in a role pill. "You" identifies the user. Neither is ever anonymous.

**Generation states are visible but not intrusive.** Thinking, streaming, and tool execution all have distinct visual representations. None of them block the user or demand attention beyond acknowledging that work is in progress.

**Tool execution is disclosed, never hidden.** Skills used to produce a response are surfaced in a compact pill. Users can inspect detail on demand. The assistant does not silently perform work.

**Errors are specific and actionable.** Error states name the problem, offer detail on demand, and provide retry where the failure is transient. Permanent failures do not show a retry action.

**The assistant never modifies user content without consent.** Actions that write to notes, tasks, files, or other owned content require either an explicit user trigger or a visible confirmation step. Silent writes are not permitted.

**Assistant surfaces use the product design language.** Chat bubbles, workspace panels, and tool disclosures all use the same tokens, radius, spacing, and motion as the rest of sideBar. Visually distinct treatment is used only where it reinforces meaning, not to mark the AI as foreign.

---

## Chat conversation

### Message structure

Each message is rendered as a bubble. Bubbles share a consistent internal layout: a header row, a content body, optional workspace handoff actions, and a timestamp.

| Element | Description |
|---|---|
| Role pill | Capsule in the message header showing the assistant's configured name or "You". Inverted fill relative to color scheme (white on black / black on white) for strong contrast |
| Content body | `SideBarMarkdown` rendered in `.chat` style, text-selectable |
| Tool pill | Appears in header row when one or more skills were used; tappable to reveal detail |
| Error pill | Appears in header row when the message has an error status |
| Retry button | Circular arrow button in header row; only shown on the latest retryable failure |
| Copy button | Icon button (`doc.on.doc`) in the header row, trailing-aligned. Transitions to `checkmark.circle.fill` with inverted fill for 1.5s on tap, then resets. Disabled and dimmed while the thinking placeholder is visible. Clipboard auto-clears after 30 seconds |
| Workspace actions | Inline action buttons below content body when the message produced workspace surface targets |
| Timestamp | Short time string, trailing-aligned below content |

Assistant bubbles use `surface` color. User bubbles use `muted` color.

### Generation states

| State | Header indicator | Body |
|---|---|---|
| Waiting for first token | Loading indicator (14px inline) left of role pill | "Thinking..." placeholder text in secondary style |
| Streaming | Loading indicator (14px inline) left of role pill | Content revealed progressively via character-paced reveal |
| Thinking dismissal | Loading indicator fades out as first token arrives | "Thinking..." text erases character by character before content takes its place |
| Complete | `SuccessCheckBadge` (14px) briefly appears in header where the loading indicator was, then fades after ~1.5s | Fully rendered markdown, copy button enabled |
| Error | Error pill in header row (warning triangle + short label, tappable for detail) | Rendered partial content (if any) |

The `accessibilityReduceMotion` environment value must be respected for the thinking dismissal animation — when reduce motion is active, the dismissal transition is instant rather than animated.

---

## Tool call disclosure

When the assistant uses one or more skills to produce a response, a tool pill appears in the message header row alongside the role pill.

| Format | When shown |
|---|---|
| Icon + skill name | Single skill |
| Icon + "N skills used" | Multiple skills |
| Icon only | Width-constrained contexts |

Tapping the pill opens a popover (sheet on compact).

**Single skill:** go straight to detail — no list step.

**Multiple skills:** show a list first (name, status indicator, status label), then detail for the selected skill.

**Skill detail view:**

1. **Summary** — a human-readable description of what the skill did (e.g. "Deleted note: My Shopping List"). This is the primary content.
2. **Workspace surface links** — action buttons to open any surfaces produced by this skill.
3. **Prompt preview** — collapsible section showing system prompt sections, budget report, and prompt content. Available to all users for transparency into what the assistant was working with.
4. **Technical detail** — collapsible section with raw parameters and result payload, for power users and debugging.

**Status colors:**

| Status | Color |
|---|---|
| Pending | `textSecondary` |
| Success | `textPrimary` |
| Error | `error` |

The skill icon is resolved per-tool via `SkillIconResolver`. Multi-skill pills use a stacked layers icon when icons diverge across tools.

### Active tool banner

During live tool execution (while streaming is in progress), a banner appears above the input bar showing the currently executing skill. The banner shows the skill name, a status label, and a status indicator:

- Running: inline loading indicator
- Success: `SuccessCheckBadge` (16pt)
- Error: warning triangle in `error` color

---

## Errors and retry

Chat errors are surfaced at the message level, not as modal interruptions.

### Error pill

An error pill appears in the message header row when a message has `.error` status and a non-empty error payload. The pill shows a warning triangle and a short pill text label. Tapping reveals an error popover with:

- Error title
- User-facing message
- Request ID (when available, for support)
- Technical details (when available, secondary style, text-selectable)

### Retry

A circular retry button appears immediately after the error pill, but only on the latest retryable error. If there are multiple failed messages, only the most recent retryable one shows the retry button. This prevents ambiguity about which failure is being retried.

During an active retry attempt, the retry button replaces its arrow icon with a mini `ProgressView`. The button is disabled for the duration.

Permanent failures (e.g. context limit exceeded, content policy) do not show a retry button. The error pill remains for disclosure but retrying would not change the outcome.

---

## Workspace surfaces

Workspace surfaces are assistant-generated content panels rendered alongside the chat in the workspace layout. They are the assistant's primary way of returning structured work product.

### Surface types

| Type | Content |
|---|---|
| Markdown | Scrollable markdown document, text-selectable |
| Table | Key-value pairs with a summary |
| Chart | Chart placeholder with summary (native chart rendering future state) |
| Map | Map placeholder with location and summary (native map rendering future state) |
| Form | Field inputs with a summary |
| Action panel | Summary text with primary and secondary action buttons |

### Surface header

Every workspace surface has a consistent header:

- Icon (surface-type-specific SF Symbol)
- Title (assistant-supplied or "Agent Workspace" fallback)
- Subtitle (surface type label)
- Action row: expand toggle, options menu (copy, share, download), refresh, close

Capabilities (refresh, close) are declared per-surface by the assistant and may not all be present.

### Surface actions

| Action | Format | Availability |
|---|---|---|
| Copy markdown | Menu item | Markdown and text surfaces |
| Share text | Menu item | All surfaces with a text payload |
| Download as .md | Menu item | Markdown and text surfaces |
| Refresh | Header button + menu item | Surface-declared |
| Close | Header button + menu item | Surface-declared |

### Workspace expand

On iPad and Mac, workspace surfaces can be expanded to full-pane width via an expand toggle in the surface header. On iPhone, this is not applicable.

---

## Assistant handoffs

When a skill produces a result that corresponds to a product destination (a note, file, task, website, or other sideBar surface), the assistant surfaces inline action buttons in the message row below the content body.

### Inline actions

| Count | Layout |
|---|---|
| 1 target | Full-width prominent button (`.borderedProminent`) centered in the message |
| 2+ targets | Horizontal scrolling row of bordered buttons |

Action labels come from the workspace surface target. Icons use the relevant section's SF Symbol.

Tapping an action routes to the target via `AppEnvironment.presentAgentSurface(...)`, which converts to a deep link and routes through the standard handler. See [Handoffs](./handoffs) for routing rules.

---

## Confirmation cards

Destructive skill actions (delete note, delete task, delete website, etc.) require explicit user confirmation before execution. The confirmation is presented as an inline card in the chat message area, not as a modal interruption.

### Confirmation card anatomy

When the backend receives a guarded tool call, it emits a `tool_confirmation_requested` event before executing. The inline card renders:

- The skill name and a plain-language summary of what will happen
- The entity name being affected
- **Accept** and **Decline** buttons
- An expiry indicator (the confirmation has a short TTL)

Both buttons show a loading state while the decision request is in flight. Once resolved, the card updates to reflect the decision and disables further interaction.

### Decline behaviour

When the user declines, the backend injects a deterministic "declined" tool result into the assistant's context so the assistant can acknowledge the refusal and continue the conversation without retrying the same action.

### Guarded tool scope

The following tools require confirmation:

| Tool | Undo supported |
|---|---|
| Delete Note | Yes |
| Delete Note Folder | Yes |
| Delete Website | Yes |
| Delete Task | Yes |
| Delete Project | Yes |
| Delete Group | Yes |
| Delete File | No |

File deletion is guarded but not undoable because it involves destructive storage cleanup.

---

## Undo

For reversible destructive actions (soft-delete-backed entities), the assistant surfaces an inline undo action after successful execution.

### Undo card anatomy

After a confirmed and executed reversible delete, the backend emits an `undo_available` event with a short-lived token. The inline undo card renders:

- A summary of what was deleted
- An **Undo** button
- A visual indication that the window is limited

The undo button shows a loading state while the undo request is in flight. Once the token expires or is consumed, the card resolves and the undo action is no longer available.

### Undo scope

Undo is supported for notes, note folders, websites, tasks, projects, and groups. Hierarchical deletes (e.g. deleting a project that contains tasks) restore the full hierarchy deterministically. File deletion is explicitly not undoable.

---

## Proactive surfaces

The assistant reaches users outside of chat through the notification system. Proactive delivery uses the five-category notification model defined in [Handoffs — Push notifications](./handoffs#push-notifications). Each proactive notification has a deep link target and routes through the standard handler on tap.

In-app proactive surfaces (morning digest destination, future assistant inbox) are not yet designed. They will follow the same product design language as workspace surfaces.

---

## Configurability

The assistant's display name is user-configurable via Settings. All UI references to the assistant — role pills, settings section titles, and copy — must use `assistantDisplayName` from `SettingsViewModel`, never a hardcoded string.

The user is always identified as "You". This is not configurable.

---

## Rules summary

1. **Every assistant message carries a role pill with the assistant's configured name.** Never render an assistant message without identification.
2. **Thinking and streaming states are always visible.** Do not suppress the loading indicator or thinking placeholder while waiting for content.
3. **Tool execution is disclosed via a skill pill on every message that used skills.** The skill pill must be present even if the user is unlikely to tap it.
4. **Retry is shown only on the latest retryable failure.** Multiple error pills may exist in a conversation; only one shows a retry action.
5. **The assistant never silently writes to user content.** Any skill that creates or modifies notes, tasks, files, or other owned content must be surfaced in the tool disclosure.
6. **Destructive delete tools always require confirmation.** Execution is paused until the user accepts or declines. No exceptions for in-scope tools.
7. **Confirmation and undo cards are inline, never modal.** They appear in the message area as part of the conversation flow.
8. **Decline is final and feeds back into the assistant.** A declined confirmation injects a deterministic result into the model context so the assistant can respond without retrying.
9. **Workspace surface headers follow the standard layout.** Icon, title, subtitle, and action row in that order. Never omit the header.
10. **Workspace handoff actions use inline buttons, not text links.** One target: prominent full-width button. Multiple targets: bordered horizontal scroll.
11. **All assistant navigation routes through the deep link system.** `presentAgentSurface` converts to `sidebar://` before routing. No direct navigation bypasses the handler.
12. **`assistantDisplayName` must be used for all references to the assistant.** Never hardcode a name.
13. **Reduce motion must be respected for all assistant animations.** Thinking dismissal, streaming reveal, and any other assistant-driven motion must have instant fallbacks.

---

## Related docs

- [Handoffs](./handoffs)
- [Wait UX](./wait-ux)
- [Feedback and Haptics](./feedback-and-haptics)
- [Navigation](./navigation)
- [Voice and Content](../voice-and-content)
- [Implementation Gaps](../implementation-gaps)
