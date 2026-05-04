---
title: Content Presentation
description: How the AI assistant opens and displays content in the workspace when skills produce viewable or editable results.
---

## Purpose

Define the universal pattern for presenting skill-produced content in the workspace. When the assistant creates a note, saves a website, returns search results, or produces any other viewable content, this pattern governs how that content appears, where it appears, and how the experience differs across platforms.

This is the coordination layer between [AI Assistant UI](./ai-assistant-ui) (what surfaces look like), [Navigation](./navigation) (how layout and routing work), and [Wait UX](./wait-ux) (how loading and streaming behave). It does not replace any of those patterns.

---

## Classification

Every skill result is classified into one of two categories based on signals the backend emits:

### Content-bearing

The result produced something the user can view or edit. A result is content-bearing if it includes either:

- A `workspace_patch` with a `present_agent_surface` operation, or
- A `workspace_patch` with an `open_entity` operation for a built-in app destination, or
- A typed event with `open_in_workspace: true`

| Category | Examples |
|---|---|
| Domain object creation/read/update | Create note, edit note, save website, write file, create task |
| Dynamic surfaces | Web search results, memory display, any markdown/table/chart/map/form/action panel surface |
| Previews | Prompt preview |
| Off-platform action results | A sent email body, a calendar event confirmation, or any external action that returns displayable content |

### Action-only

The result changed state but produced nothing to display.

| Category | Examples |
|---|---|
| Metadata mutations | Pin, archive, move, delete, rename |
| System changes | Theme, settings, identity, soul |
| Memory operations | Create, update, delete memory |

Action-only results keep their current behaviour: chat pill disclosure, no workspace change. The remainder of this pattern applies only to content-bearing results.

---

## Coordinated dispatch

Content-bearing results are presented through a single coordinated workspace action. This is the only mechanism skills use to display content. No skill implements its own navigation logic.

### Dispatch contract

| Field | Type | Purpose |
|---|---|---|
| Content descriptor | Domain object ID or `AgentWorkspaceSurfaceDescriptor` | What to show in the main pane |
| Section | `AppSection?` | Which left panel section to switch to, or nil for dynamic surfaces |
| Pane | `WorkspacePane` | Which pane to target (primary by default) |
| Native route URL | `sidebar://` URL, optional for dynamic surfaces | Stable route identifier for built-in app entities and fallback buttons |

The dispatch is the single source of truth for both platforms. On iPad/Mac it drives the workspace state. On iPhone it produces the inline action button data.

### Built-in entity opens

When the user asks the assistant to open an existing sideBar destination, the assistant uses explicit open actions. Those actions emit `open_entity` workspace patches with the target entity, section, pane, and canonical `sidebar://` route URL.

| Open action | Native route |
|---|---|
| Open note | `sidebar://notes/{noteId}` |
| Open website | `sidebar://websites/{websiteId}` |
| Open file | `sidebar://files/{fileId}` or `sidebar://files/{path}` when only a path is available |
| Open chat | `sidebar://chat/{chatId}` |
| Open scratchpad | `sidebar://scratchpad` |
| Open tasks today | `sidebar://tasks/today` |
| Open task | `sidebar://tasks/task/{taskId}` |
| Open task project | `sidebar://tasks/project/{projectId}` |
| Open task group | `sidebar://tasks/group/{groupId}` |

Native clients resolve these routes locally when the app is active rather than bouncing through the operating system. Fallback buttons in the assistant message replay the same route payload. Skill pill popovers do not duplicate these route actions.

File opens may arrive with a stored file ID or a storage path. Native routing resolves paths to local file records before selecting the file, refreshing the file list once if needed.

If native loading fails, the app records a concise `last_open_error` in the next chat request context. The assistant can then acknowledge the failure and choose a recovery path instead of assuming the content opened successfully.

---

## Content type to section mapping

| Content type | Left panel section | Main pane view |
|---|---|---|
| Note (create, read, update) | Notes | Note editor |
| Task (create, read, update) | Tasks | Task detail |
| Website (save, read) | Websites | Website detail |
| File (write, upload) | Files | File viewer |
| Chat | Chat | Chat conversation |
| Scratchpad | Chat | Scratchpad presentation |
| Dynamic surface (markdown, table, chart, map, form, action panel) | No switch (current section) | `AgentWorkspaceSurfaceView` |

**Domain object + dynamic surface in same tool call:** the domain object takes priority for the left panel switch. The dynamic surface is available via its inline action button in chat.

**Unknown content type:** defaults to the dynamic surface path (no panel switch, content in main pane). Update this table when a dedicated section is added.

**Off-platform action results:** follow the dynamic surface path. The backend includes a `workspace_patch` if the content warrants display, or omits it for chat-pill-only acknowledgement.

---

## Platform behaviour

### iPad/Mac (auto-present)

When a content-bearing result arrives:

1. **Left panel switches** to the section matching the content type per the mapping table. No switch for dynamic surfaces.
2. **Main pane presents** the content: built-in detail view for domain objects, `AgentWorkspaceSurfaceView` for dynamic surfaces.
3. **Timing**: immediately on tool result arrival, even if the assistant is still streaming.
4. **Inline action button still rendered** in the chat message so the user can return to the content later.

The swap is instant with no transition animation, consistent with the existing descriptor-swap pattern defined in [Navigation](./navigation).

### iPhone (deferred via button)

On iPhone (compact width), the dispatch does not mutate `WorkspaceStore` or trigger navigation. The content descriptor produces an inline action button in the chat message.

1. **No automatic navigation.** The user stays in the chat conversation.
2. **Inline action button** appears immediately on tool result arrival, even mid-stream.
3. **Tapping the button** pushes the content via `navigationDestination` (max depth 2, per [Navigation](./navigation)).
4. **Swiping back** returns to the chat conversation.

---

## Updates to displayed content

When the assistant updates content that is already displayed in the main pane (e.g. edits an open note):

1. Display surfaces **refresh in-place** with no transition, animation, or indicator.
2. Bound collaborative surfaces preserve active local editing state and merge through the bound entity's normal editor/write path rather than replacing the whole surface payload.
3. The left panel does not re-switch (it is already on the correct section).
4. The chat thread provides visual acknowledgement via the tool pill. No workspace-level indicator is needed.

---

## Multiple results in one turn

Each content-bearing result triggers the presentation lifecycle independently. Each result updates the left panel and main pane as it arrives. The final workspace state reflects the **last content-bearing result** in the turn. Earlier results remain accessible via their inline action buttons in chat.

---

## Rules summary

1. **Every skill result is classified as content-bearing or action-only.** Classification is determined by the backend signal: `workspace_patch` with `present_agent_surface` or `open_entity`, or a typed event with `open_in_workspace: true`. The client does not infer classification.
2. **Content-bearing results use the coordinated dispatch.** A single workspace action handles left panel switching and main pane content presentation. No skill implements its own navigation logic.
3. **iPad/Mac auto-presents on tool result.** Content appears immediately in the main pane, even mid-stream. No user action required.
4. **iPhone uses the inline action button.** No automatic navigation. The user taps to view content.
5. **The left panel switches to the matching section for domain objects.** Notes, tasks, websites, and files each map to their section. Dynamic surfaces do not switch the panel.
6. **Updates refresh in-place.** Display content already shown in the main pane refreshes silently when the assistant updates it. Bound collaborative surfaces preserve active local edits and merge through the bound entity's normal editor/write path.
7. **Last result wins for multiple content-bearing results.** Each triggers the lifecycle independently. The final workspace state reflects the last result. Earlier results are accessible via inline action buttons in chat.
8. **The inline action button is always rendered.** On iPad/Mac it serves as a "return to content" affordance even though content was auto-presented. On iPhone it is the sole navigation trigger.
9. **Action-only results are unaffected.** Pin, delete, archive, theme, settings, and memory operations keep their current chat pill disclosure with no workspace change.
10. **New content types default to the dynamic surface path.** No panel switch, content in the main pane. The mapping table is updated when a dedicated section is added.
11. **Built-in app entity opens are route-backed.** Open actions use `open_entity` patches, canonical `sidebar://` routes, local-first native resolution, and message-level fallback buttons.
12. **Open failures are fed back to the assistant.** Native open failures are recorded in chat context so the assistant does not claim content opened when the app could not load it.

---

## Related docs

- [AI Assistant UI](./ai-assistant-ui)
- [Navigation](./navigation)
- [Wait UX](./wait-ux)
- [Handoffs](./handoffs)
- [Sidebar Model](./sidebar-model)
