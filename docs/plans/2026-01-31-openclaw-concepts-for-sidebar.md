# OpenClaw Concepts to Explore for sideBar

Purpose: capture OpenClaw concepts that may transfer well to sideBar, why they matter, and how they could map onto sideBar's current architecture.

Structure per item:
- Why interesting
- sideBar touchpoints
- Potential fit
- Design notes (service layer / API / data / UI)
- Risks / constraints
- Explore next

## 1) System prompt (owned + structured)
- Why interesting: OpenClaw builds a full, sectioned prompt per run with explicit tool, skills, time, and runtime sections plus a minimal mode for subagents.
- sideBar touchpoints: `backend/api/services/prompt_context_service.py`, `backend/api/prompts.py`, `backend/api/prompt_config.py`, `backend/api/routers/chat.py`.
- Potential fit: Standardize the system prompt into named sections so the model gets consistent context and tool guidance, and make it easier to reason about prompt composition over time.
- Design notes:
  - Service layer: extend `PromptContextService.build_prompts()` to return a structured prompt (sections + metadata) and a flattened string.
  - Data model: optionally store a prompt report (sections, sizes, source) on the conversation or in a separate table for diagnostics.
  - API: expose a "prompt preview" endpoint or SSE event (existing `prompt_preview` tool already returns system/first prompts in `claude_streaming`).
  - UI: add a small "prompt preview" panel for debugging, or surface key sections (profile, location, open context).
- Risks / constraints: prompt growth vs model limits; must keep prompt deterministic and avoid leaking private data.
- Explore next: audit `build_system_prompt()` and `PromptContextLimits` to identify section boundaries and what can be toggled.

## 2) Compaction (auto + manual)
- Why interesting: OpenClaw compacts older history into a summary, persists it, and retries automatically when context overflows.
- sideBar touchpoints: conversation JSONB in `backend/api/models/conversation.py`, history assembly in `backend/api/routers/chat.py`.
- Potential fit: Keep long conversations usable while avoiding JSONB size bloat and model context overflow.
- Design notes:
  - Service layer: add a `ConversationCompactionService` that summarizes older messages into a compact summary entry and trims history.
  - Data model: store `compaction_count`, `compaction_summary`, or inject a synthetic "summary" message into `messages`.
  - API: add `/conversations/{id}/compact` or auto-trigger compaction when history length or token estimates exceed a threshold.
  - UI: show a compacted marker in chat history, with ability to expand a summary.
- Risks / constraints: summary quality impacts future replies; requires token estimation or heuristic limits; needs soft delete rules.
- Explore next: estimate current average message sizes and define safe thresholds (or use model metadata if available).

## 3) Agent workspace (bootstrap files)
- Why interesting: OpenClaw uses a workspace with bootstrap files (SOUL.md, IDENTITY.md, USER.md, MEMORY.md) that are injected into prompt context.
- sideBar touchpoints: workspace files in R2 (see storage + ingestion services), file ingestion derivatives in `backend/api/services/file_ingestion_service.py`.
- Potential fit: A user-editable "assistant workspace" could unify identity, memory, and operating rules while remaining transparent.
- Design notes:
  - Service layer: define a logical workspace path per user (e.g., `/workspace/{user_id}/...`) stored in R2, and load key files during prompt assembly.
  - Data model: optionally mirror workspace metadata in DB for search and UI browsing.
  - API: extend open context to include workspace docs; add endpoints to list/edit workspace files.
  - UI: add a "Workspace" panel that exposes SOUL/IDENTITY/USER style docs.
- Risks / constraints: ensure workspace content is safe to inject; enforce size limits and sanitization; avoid hard delete.
- Explore next: map existing ingestion format for ai.md derivatives to reuse as workspace context.

## 4) "Soul" / identity layer
- Why interesting: Separates persona from memory and system rules; consistent identity across sessions.
- sideBar touchpoints: user profile settings in `backend/api/services/user_settings_service.py`; prompt templates in `backend/api/prompt_config.py`.
- Potential fit: Split "assistant identity" from user profile and system prompts, giving a stable persona.
- Design notes:
  - Service layer: add `AssistantIdentity` model (name, tone, boundaries, values) with default values.
  - Prompt: inject identity block as a dedicated section in `build_system_prompt()`.
  - UI: expose an "Assistant identity" editor separate from user profile.
- Risks / constraints: avoid conflicting instructions between identity and user profile; needs clear precedence.
- Explore next: identify current prompt template variables that should move into identity vs user profile.

## 5) Memory policy + recall guidance
- Why interesting: OpenClaw uses explicit memory retrieval instructions and curated memory files.
- sideBar touchpoints: `backend/api/services/memory_service.py`, `backend/api/services/memory_tools/*`, memory tool events in `backend/api/services/claude_streaming.py`.
- Potential fit: Make memory behavior predictable, auditable, and user-controlled.
- Design notes:
  - Service layer: add memory categories (facts, preferences, projects) and recall hints; standardize path scheme (`/memories/{category}/{name}`).
  - Prompt: add a memory section that tells the assistant when to search or ask.
  - UI: add a "Memory ledger" view with categories and recent updates.
- Risks / constraints: existing memory delete is hard delete; sideBar rules prefer soft delete for user data.
- Explore next: evaluate if memory records should get `deleted_at` and a simple category schema.

## 6) Markdown formatting pipeline (IR -> chunk -> render)
- Why interesting: OpenClaw uses a single Markdown parse step, then renders per surface with safe chunking.
- sideBar touchpoints: `docs/MARKDOWN_STYLES.md`, TipTap editor components and read-only renderers.
- Potential fit: sideBar is UI-first, but an IR-based formatter could help if outbound messages or exports need consistent formatting and chunking.
- Design notes:
  - Service layer: optional; mostly frontend. Introduce a shared Markdown parser/IR for export or notifications.
  - UI: could use IR for chat/notifications if sending to external surfaces in the future.
- Risks / constraints: may be unnecessary unless sideBar adds multi-channel delivery.
- Explore next: identify current markdown renderers and whether an IR would simplify table/format consistency.

## 7) Cron jobs (scheduler)
- Why interesting: OpenClaw runs cron jobs inside the gateway, with persistent job store and isolated sessions.
- sideBar touchpoints: task services (`backend/api/services/task_service.py`, `backend/api/services/task_sync_service.py`), recurrence logic (`backend/api/services/recurrence_service.py`).
- Potential fit: background jobs for summaries, reminders, and automation without mixing with main chat flow.
- Design notes:
  - Service layer: add a scheduler service (maybe via `backend/workers`) and a `cron_jobs` table (soft delete).
  - API: endpoints for create/list/run, plus SSE notifications via change bus.
  - UI: scheduling UI in tasks or a new automation panel.
- Risks / constraints: background execution needs safe quotas, dedupe, and error handling.
- Explore next: assess if recurrence logic can be reused for cron job schedules.

## 8) Heartbeat loop (periodic main-session checks)
- Why interesting: periodic "light touch" agent turns that only surface actionable items; OK acknowledgments are suppressed.
- sideBar touchpoints: SSE eventing (`backend/api/services/claude_streaming.py`, `backend/api/routers/events.py`) and push notifications (`backend/api/services/push_notification_service.py`).
- Potential fit: proactive, low-noise check-ins (daily summary, task nudge, inbox monitoring).
- Design notes:
  - Service layer: add a heartbeat runner that can enqueue a system event and run the assistant at intervals.
  - Data: store last heartbeat timestamp and per-user config in settings.
  - UI: allow configuring cadence and delivery target (in-app only or push).
- Risks / constraints: avoid notification fatigue; needs opt-in and quiet hours.
- Explore next: define a minimal "heartbeat prompt" and OK suppression behavior.

## 9) Session model (main vs isolated)
- Why interesting: OpenClaw keeps background work isolated from main chat history.
- sideBar touchpoints: conversation model in `backend/api/models/conversation.py` and routing in `backend/api/routers/chat.py`.
- Potential fit: support background sessions for cron, automation, and long-running tasks.
- Design notes:
  - Data model: add `conversation_type` or `session_kind` to conversations (main, automation, background).
  - API/UI: filter conversations by type; hide background sessions by default.
  - Service layer: route scheduled runs into isolated sessions to avoid chat clutter.
- Risks / constraints: needs careful UX to avoid "missing" background output.
- Explore next: define how summaries from background sessions are surfaced in main UI.

## 10) Device / environment "nodes"
- Why interesting: OpenClaw treats devices as nodes with explicit capabilities (camera, location, notifications).
- sideBar touchpoints: device tokens + APNs (`backend/api/routers/device_tokens.py`, `backend/api/services/push_notification_service.py`), iOS app architecture docs.
- Potential fit: a simple capability registry for devices to support richer actions (notify, capture, location requests).
- Design notes:
  - Service layer: store device capabilities alongside tokens; add a "device action" tool.
  - API: endpoints to register device capabilities and call device actions.
  - UI: device settings page to opt into camera/location/notification features.
- Risks / constraints: security and privacy; must include explicit user consent per capability.
- Explore next: inventory current iOS/macOS app capabilities and how they could be surfaced safely.

## 11) Presence + operational transparency
- Why interesting: OpenClaw emits presence/heartbeat/health events for UI surfaces.
- sideBar touchpoints: change bus SSE (`backend/api/services/change_bus.py`, `backend/api/routers/events.py`), chat SSE (`backend/api/services/claude_streaming.py`).
- Potential fit: improve user trust and debuggability (show "thinking", "running tool", "saving note").
- Design notes:
  - Service layer: standardize event types (presence, tool start/end, long-running task states).
  - API: extend `/events` to include richer event types beyond task changes.
  - UI: add a small status surface in chat header or sidebar.
- Risks / constraints: avoid noisy UI; need debounced events.
- Explore next: inventory current SSE events (chat stream + change bus) and define a minimal presence schema.

## 12) Offline / sync semantics
- Why interesting: OpenClaw gateway acts as a durable control plane; jobs and sessions persist and replay cleanly.
- sideBar touchpoints: offline sync services for notes, tasks, files, and websites (`backend/api/services/notes_sync_service.py`, `task_sync_service.py`, `files_sync_service.py`, `websites_sync_service.py`).
- Potential fit: unify sync behavior across domains and extend to memories or workspace files.
- Design notes:
  - Service layer: introduce a shared operation log schema or helper utilities to reduce duplicated sync logic.
  - Data: add soft delete + conflict handling for memories and workspace files.
  - UI: consistent "sync status" indicators across notes/tasks/files/websites.
- Risks / constraints: conflict resolution policies must be consistent; avoid silent overwrites.
- Explore next: identify which domains still lack sync or conflict policies (memories, scratchpad, settings).
