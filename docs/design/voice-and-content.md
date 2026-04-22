---
title: Voice and Content
description: Product voice, UI writing rules, and content standards for sideBar across all surfaces.
---

## Purpose

Define the product voice, writing rules, and content standards for sideBar. This covers how all developer-authored text should sound across UI copy, empty states, errors, notifications, and labels.

---

## Why this matters

Words are part of the product experience. Inconsistent or careless copy erodes trust and makes the product feel unfinished even when the visuals are strong. A single voice guide lets every developer-authored string — whether written by a human or an AI coding agent — follow the same standards.

---

## The identity boundary

sideBar has three distinct voice layers. These must not be collapsed:

| Layer | Who controls it | What it covers |
|---|---|---|
| **Product voice** | Developer-authored | UI copy, labels, empty states, errors, notifications, docs, marketing |
| **Assistant identity** | Self-managed by sideBar in Settings | The assistant's name, tone, values, and how it communicates |
| **User preferences** | User-controlled in Settings | Communication style and working relationship with the assistant |

This document covers the product voice only. The assistant's own identity is not specified here.

---

## Foundational character

The product voice does not exist in isolation from sideBar's self-defined identity, but it does not depend on it either. sideBar's identity and soul are authored by sideBar itself during onboarding calibration and evolve over time. The product voice is developer-authored and stable.

The product voice should be consistent with the hard constraints on sideBar's character: not sycophantic, not generic, not dishonest about limitations, not passive when something matters. Beyond those constraints, sideBar's specific tone, values, and personality are its own to define for each user.

Product copy should feel like it comes from the same source as sideBar's character: direct, not sycophantic, honest, precise.

**What this means in practice**:
- Do not pad or soften copy to seem friendlier: "Your note was saved successfully!" → "Saved"
- Do not hedge: "This might take a moment" → "Loading..."
- Do not flatter: "Great question!" has no equivalent in product copy
- Do be honest about failure: say what happened, not just that something went wrong
- Do be precise: one clear sentence beats three vague ones

---

## Two registers

sideBar uses two distinct voice registers depending on surface:

### Ambient register

Used in: Notes, Tasks, Websites, Files — and all supporting UI (settings, navigation, system chrome).

**Character**: Calm, capable, and functional. Fades into the background. Never opinionated, never chatty. Gives the user confidence without drawing attention to itself.

**Tone**: Expert without being technical. Direct without being cold. Tells the user what they need, nothing more.

**Examples**:
> "Your note is saved." "Ready when you are." "Can't connect right now." "No notes yet."

### Engaged register

Used in: Chat messages, skill execution UI, assistant framing, chat empty states, skill descriptions, the Skills Store.

**Character**: Grounded, human, and warm. Slightly more personal than the ambient register. Has personality without being casual or performative. This is where sideBar's character is most present.

**Tone**: Acknowledges the user's context. Direct but not cold. Can be warm without being effusive.

**Examples**:
> "You haven't added anything yet." "That didn't work. Let's try again." "All caught up." "I couldn't finish this response — it needed too many steps. Try a narrower follow-up."

---

## Icons over text

sideBar prioritises iconography over labels where the meaning is clear. Icons are more compact, convey meaning faster, and reduce visual noise. Text is used where a symbol alone would be ambiguous or where accessibility requires it.

**Rules**:
- When a well-understood SF Symbol exists for an action or concept, prefer it over a text label
- Navigation icons in the sidebar rail never have text labels
- Toolbar and header actions use icons by default; add a text label only when the action is genuinely ambiguous to new users
- Context menus may use icon + text to aid discoverability
- Never use an icon without an `.accessibilityLabel` — the icon is a visual shorthand, not a substitute for a meaningful label
- When an icon is paired with text, the text is the canonical label; the icon is supporting

**Where text always wins**:
- Destructive confirmation alerts: always use a text label ("Delete note") so the consequence is unambiguous
- Error messages: icons may support but text must carry the meaning
- Empty states: icons may be used decoratively but copy must communicate what to do next

Full iconography guidance belongs in `foundations/iconography.md`.

---

## Writing rules

### Buttons and CTAs

- Use verb phrases: "Add note", "Delete", "Save changes", "Try again"
- Do not use filler: "Click here", "Go", "Submit"
- Destructive actions should name the thing being destroyed: "Delete note", not just "Delete"
- Confirmation button in a destructive alert should match the action label: "Delete" not "OK"

### Field labels

- Short and literal: "Title", "Due date", "Website URL"
- No colons on labels
- Title case for labels

### Placeholder text

- Indicate the expected input, not instruct: "Note title" not "Enter a title for your note"
- Sentence case for placeholders

### Helper text

- Only add when the input is genuinely ambiguous
- One sentence maximum
- Do not repeat the label

### Empty states

Empty states should tell the user what will appear here and give them the next action if one exists. Keep them short and direct.

**Ambient register** — useful and direct, no trailing period:

| Surface | Preferred copy |
|---|---|
| Notes (empty) | "No notes yet" |
| Notes (archived) | "No archived notes" |
| Notes (search, no results) | "No matching notes" |
| Tasks (empty) | "No tasks yet" |
| Websites (empty) | "No websites yet" |
| Websites (archived) | "No archived websites" |
| Files (empty) | "No files yet" |
| Files (search, no results) | "No results" |
| Chat (empty conversation list) | "No conversations" |

**Consistency rule**: No trailing period on empty state titles.

### Unavailable offline states

Unavailable-offline titles should explain that the content exists, but this device does not have it cached yet. Keep them short and direct.

| Surface | Preferred copy |
|---|---|
| Note detail | "This note isn't available offline yet" |
| Website detail | "This page isn't available offline yet" |
| File detail | "This file isn't available offline yet" |
| Chat detail | "This chat isn't available offline yet" |

**Engaged register** — can be warmer:

| Surface | Preferred copy |
|---|---|
| New chat (no messages) | A short prompt or starter, not a blank void |
| Skills (none configured) | "You haven't added any skills yet." |

### Error messages

Errors should be honest, direct, and specific enough to help the user. Never alarming, never vague.

**Rules**:
- Say what happened, not just that something went wrong
- If the user can act, tell them what to do: "Try again", "Sign in again", "Check your connection"
- Avoid passive constructions: "An error occurred" is vague; "The request timed out" is specific
- Do not use first-person "I" in system-level errors. Reserve first-person for assistant responses in the chat thread

**Preferred patterns** (from `ErrorMapping.swift`):

| Situation | Message |
|---|---|
| Provider busy | "The AI provider is busy right now. Please try again in a moment." |
| Rate limited | "The AI provider is rate limited right now. Please wait a moment and try again." |
| Timed out | "The request timed out. Please try again." |
| Network interrupted | "The network connection was interrupted. Please try again." |
| Context too large | "This request is too large to retry without reducing context." |
| Auth failed | "Authentication failed. Please sign in again." |
| Request cancelled | "The request was cancelled before it completed." |

### Success messages

Success states should be quiet unless the action was significant.

- Inline saves: silent or a brief pill ("Saved")
- Destructive confirms: silent — the item disappearing is confirmation enough
- Significant actions (skill execution complete, sync finished): a short acknowledgement is appropriate

Settings changes are silent while healthy. If a settings write fails, route the user to queued changes rather than showing a dedicated settings save pill.

### Loading and waiting states

Loading states should not be abandoned. If the user is waiting, the UI should acknowledge it.

- Short waits (under 1s): no explicit loading indicator needed
- Longer waits: show a loading indicator; do not show a blank screen
- Indeterminate long waits (AI streaming): show progress; do not block the UI

Full guidance belongs in `patterns/wait-ux.md`.

### Notifications and toasts

- One sentence, no punctuation at the end unless it is a complete verb phrase
- State what happened: "File attached", "Note deleted", "Failed to attach file"
- Avoid "Successfully...": "File saved" not "File saved successfully"

---

## Terminology

These terms should be consistent across UI, docs, and marketing:

| Term | Use | Avoid |
|---|---|---|
| sideBar | Product name, lowercase 's' | SideBar, Sidebar |
| Chat | The Chat section | Conversations (in UI labels) |
| Notes | The Notes section | Documents, Memos |
| Tasks | The Tasks section | To-dos, Todos |
| Websites | The Websites section | Bookmarks, Links |
| Files | The Files section | Documents, Attachments |
| Skills | AI capabilities in the Skills Store | Integrations, Plugins, Apps |
| Scratchpad | The quick-capture surface | Scratch pad, Quick notes |
| Workspace | The multi-panel layout | Dashboard, Home |
| Section | A top-level area (Chat, Notes, etc.) | Tab, Category, Module |

**AI-specific terminology**:

| Term | Use | Avoid |
|---|---|---|
| sideBar (as assistant) | The assistant speaking in first person | "The AI", "ChatGPT", "The model" |
| Skill | A specific capability | Tool, Feature, Integration (in UI) |
| Tool use | Technical term — use sparingly in UI | Show only in developer-facing contexts |

**Subscription terminology**:

| Term | Use | Avoid |
|---|---|---|
| Free | The no-cost tier (productivity suite only) | Free plan, Free tier (in UI copy; "Free" alone is sufficient) |
| Plus | The entry-level paid tier | Basic, Starter, Standard |
| Pro | The full-featured paid tier | Premium, Ultimate, Max |
| BYOK | The bring-your-own-key tier | Developer plan, API plan |
| Subscribe | The action of starting a paid plan | Purchase, Buy, Pay for |
| See plans | The universal upgrade CTA | Upgrade now, Go premium, Unlock |

**Upgrade prompt copy**:

Upgrade prompts use the engaged register. They should be warm, specific, and honest, never vague or punitive.

| Register | Example |
|---|---|
| Ambient (settings, labels) | "Upgrade to continue" |
| Engaged (chat, skill store) | "You've used all 30 messages for today. Upgrade to Pro for 150 a day, or check back tomorrow." |
| Engaged (skill gating) | "Deep research needs a Pro subscription." |
| Engaged (free user in chat) | "Subscribe to chat with sideBar" |

Rules for upgrade copy:

- Always name the specific tier required (Plus, Pro), never say "premium" or "paid"
- Always explain what the user tried to do and what unlocks it
- For cap-reached states, include the reset time so the user knows the alternative to upgrading
- Never frame the boundary as a punishment ("You've hit your limit"). Frame it as information ("You've used all 30 messages for today").

---

## Language to avoid

- **Filler confirmations**: "Got it!", "Great!", "Sure!" — never in product voice
- **Vague errors**: "Something went wrong", "An error occurred" — always be more specific
- **Alarming language**: "Warning!", "Critical error", "Fatal" — unnecessary in consumer UI
- **Overly technical terms** in user-facing copy: "null", "exception", "request failed with status 500"
- **Redundant success language**: "Successfully saved", "Operation completed successfully"
- **Ellipsis abuse**: "Loading..." is fine; "Please wait..." is unnecessary; "Thinking..." only in Chat

---

## Copy drift in the current codebase

Known inconsistencies to resolve:

| Location | Current | Issue | Fix |
|---|---|---|---|
| `FilesPanel.swift` | "No files yet." | Trailing period | Remove period |
| `FilesPanel.swift` | "No results." | Trailing period | Remove period |
| `ChatToolComponents.swift` | "Skill completed successfully." / "Skill failed." | Too technical for the engaged register | Rewrite |

---

## Product voice in a few words

**Pragmatic, honest, and built to help.**

This is the short description of sideBar's product voice. It aligns with the hard constraints on sideBar's character (not sycophantic, not dishonest, not passive) while standing on its own as a developer-authored standard. It should be the shorthand used in onboarding, marketing, and as a reference point when evaluating new copy.

---

## Email templates

Transactional emails (verification, invitation, password reset) follow the same voice and colour rules as the rest of the product. The structural pattern:

| Element | Style |
|---|---|
| Logo | App icon, 56px, centred |
| Product name | 24px, weight 700, `#000000` (textPrimary) |
| Heading | 30px, weight 700, `#111111` |
| Body text | 16px, `#6b6b6b` (textSecondary) |
| De-emphasised text | 14px, `#aaaaaa` (textTertiary) |
| OTP code box | 36px, weight 700, `#f5f5f5` fill (muted), `#e5e5e5` border |
| CTA button | 16px, weight 600, `#111111` fill, `#ffffff` text, 14px radius |
| Footer | Marketing tagline from `MARKETING_COPY.tagline`, 13px, textTertiary |
| Card | `#ffffff` background, `#e5e5e5` border, 20px radius |
| Page background | `#f5f5f5` (muted) |

**Rules**:
- Use semantic colour tokens, not ad hoc hex values. Body text is textSecondary, not an arbitrary grey.
- Footer carries the marketing tagline, not a bare product name.
- Font stack is `-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif` to match the system font approach across platforms.
- Voice is ambient register: direct, no filler, no "Successfully!" language.
- New templates should follow this pattern. If a new surface needs a different layout, update this section first.

---

## Related docs

- [Design Principles](./principles)
- [System Inheritance](./system-inheritance)
- `foundations/iconography.md`
- `patterns/wait-ux.md`
- `patterns/feedback-and-haptics.md`
