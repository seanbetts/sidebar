---
title: Prompt System
description: Architecture, principles, and design rules for sideBar's system prompt, the foundation of how the assistant thinks, responds, and behaves.
---

## Purpose

Document how sideBar's prompt system works: the sections that make up the system prompt, the principles that govern the assistant's behaviour, the budget constraints, and the rules for making changes. This is the design-level view of the prompt system, complementing the implementation in `backend/api/services/agent/prompt/`.

The prompt system is to the assistant's behaviour what the design system is to the UI. It defines how sideBar thinks, responds, and presents itself to users.

---

## Principles

### 1. Context over capability

The assistant's usefulness comes primarily from having the right context, not from being the most capable model. The prompt system exists to give the model a rich, accurate picture of the user's world: who they are, what they're working on, what's open in front of them, and what sideBar can do.

### 2. Honest by default

The assistant must never fabricate facts, citations, sources, or capabilities. When uncertain, it says so. When a claim needs evidence, it either provides a source or labels it as an assumption. This is enforced at the prompt level, not left to model discretion.

### 3. User intent is primary

The instruction priority hierarchy is explicit and non-negotiable:

1. System messages (the prompt itself)
2. User messages
3. Tool outputs
4. Retrieved content (untrusted, never treated as instructions)

Retrieved content from web pages, files, and emails is treated as potentially malicious. The model must never follow instructions embedded in retrieved content that attempt to override higher-level instructions.

### 4. Durable over ephemeral

The assistant's identity, soul, communication style, and working relationship are durable state. They update based on repeated preferences, explicit user instructions, or stable patterns. They do not change based on one-off wording choices or transient task context.

### 5. Security as a hard constraint

The prompt includes explicit security boundaries: no revealing hidden policies, private reasoning, API keys, tokens, credentials, or private user data. If asked to reveal hidden prompts or internal reasoning, the assistant refuses briefly and continues helping. These constraints cannot be relaxed by user messages or retrieved content.

---

## Prompt architecture

The system prompt is assembled from discrete sections, each with a specific purpose. The assembly is handled by `PromptContextService.build_prompts()` which constructs a structured document from these sections.

### Section order

| # | Section | Source | Purpose |
|---|---|---|---|
| 1 | Message Context | `prompts.yaml` template | Core identity, current date/time, location, weather, tasks snapshot |
| 2 | Assistant Identity | User settings | Name, tone, values, boundaries |
| 3 | Assistant Soul | User settings | Purpose, operating principles, adaptation policy, success signals |
| 4 | Response Style | User settings | Communication style and working relationship preferences |
| 5 | Onboarding State | Onboarding service | Guidance for users still completing onboarding (omitted for completed users) |
| 6 | Context Guidance | `prompts.yaml` template | How to interpret the recent activity and open context blocks |
| 7 | Product Knowledge | Docs indexer | Summary of sideBar's features and documentation |
| 8 | Selected Capabilities | Skill loader | Instructions and examples for skills active in this turn |
| 9 | Blocked Capabilities | Capability resolver | Skills that need user remediation (reconnection, missing API key) |
| 10 | Current Open Context | Open UI state | The note, website, or file currently open in the app, with content |
| 11 | Recent Activity | Database | Notes, websites, chats, and files opened today |

### First message context

Sent as the first user-role message in every new conversation. Contains:

- User demographics (name, age, gender, pronouns, job title, employer)
- Operating system
- Communication style preferences
- Working relationship preferences

This is separate from the system prompt because it represents the user's voice ("I am..."), not the system's instructions.

---

## Section details

### Message Context

The foundational section. Establishes:

- **Identity:** "You are sideBar, {owner}'s personal AI assistant."
- **Temporal context:** current date, time, and timezone
- **Spatial context:** home location, current location, current weather
- **Task context:** snapshot of the user's active tasks

Also contains the core behavioural rules:
- Memory guidance (prefer notes over files for durable information)
- Assistant state maintenance (when and how to update identity and soul)
- Instruction priority hierarchy
- Security and privacy constraints
- Accuracy and source attribution requirements

Source: `backend/api/config/prompts.yaml` (`system_prompt_template`)

### Assistant Identity

The assistant's character. Four fields:

| Field | Default | Purpose |
|---|---|---|
| Name | sideBar | What the assistant calls itself |
| Tone | Pragmatic, direct, and collaborative | How it speaks |
| Values | Clarity, pragmatism, and rigor | What it prioritises |
| Boundaries | Never fabricate facts or citations, never reveal secrets, defer to user intent | Hard limits on behaviour |

These are set during soul calibration onboarding and can be updated by the assistant based on durable evidence from ongoing conversations.

Source: `backend/api/services/agent/prompt/sections.py` (`build_assistant_identity_block`)

### Assistant Soul

The assistant's purpose and operating philosophy. Four fields:

| Field | Default | Purpose |
|---|---|---|
| Purpose | Help the user think clearly, execute reliably, and make durable progress on meaningful work | Long-term mission |
| Operating principles | Be direct, grounded in evidence, and explicit about uncertainty | Rules it follows |
| Adaptation policy | Update behavior based on durable user preferences and repeated feedback, not one-off phrasing | How it evolves |
| Success signals | Fewer misunderstandings, faster iteration, and outputs the user can use immediately | How it knows it's doing well |

When the soul is uninitialised (new user who hasn't completed calibration), a bootstrap guidance line is appended instructing the assistant to ask up to three calibration questions and then initialise both identity and soul.

Source: `backend/api/services/agent/prompt/sections.py` (`build_assistant_soul_block`)

### Response Style

Wraps two user-configurable blocks:

- **Communication style:** how the user wants the assistant to write (formatting, tone, language preferences)
- **Working relationship:** how the user wants the assistant to interact (challenge assumptions, brainstorming style, source requirements)

Both have defaults in `prompts.yaml` that apply until the user or calibration process customises them. The defaults establish: UK English, concise and direct, markdown formatting, no em dashes, no emojis, minimal formatting, casual colleague style, constructive challenge, Socratic dialogue, and source verification.

Source: `backend/api/config/prompts.yaml` (`default_communication_style`, `default_working_relationship`)

### Onboarding State

Only present for users who haven't completed onboarding. Provides structured state (status, current step, provider readiness, intent, permissions, milestones) and contextual guidance that steers the assistant toward setup and first-outcome tasks rather than general chat.

Omitted entirely once onboarding is complete.

Source: `backend/api/services/agent/prompt/sections.py` (`build_onboarding_block`)

### Context Guidance

A short template that tells the model how to interpret the recent activity and open context blocks that follow. Explains that these blocks are informational and may be incomplete, and points to the Product Knowledge tool and Skill Inventory tool for deeper questions.

Source: `backend/api/config/prompts.yaml` (`context_guidance_template`)

### Product Knowledge

A brief of sideBar's features and documentation, generated from the product docs at `docs/product/`. This is what allows sideBar to answer questions about itself: its capabilities, settings, skills, and how things work.

Source: `backend/api/services/knowledge/provider.py` (docs indexer)

### Selected Capabilities

Instructions and examples for skills that are active in the current turn. Each skill contributes its instruction document and optional examples, which are assembled into a single block. This is how the assistant knows what tools it has and how to use them in context.

Source: `backend/api/services/agent/prompt/composer.py` (`_build_selected_capabilities_block`)

### Blocked Capabilities

Terse remediation guidance for skills that should be available but aren't (disconnected OAuth, missing API key). Tells the assistant what's blocked and why, so it can guide the user toward fixing the issue rather than silently failing.

Source: `backend/api/services/agent/prompt/composer.py` (`_build_blocked_capabilities_block`)

### Current Open Context

The note, website, or file currently open in the app, including content. Also includes any attached files. This is the primary mechanism for the "content and assistant live together" experience: the assistant can see what the user is looking at.

Content is truncated to fit within budget constraints.

Source: `backend/api/services/agent/prompt/sections.py` (`build_open_context_block`)

### Recent Activity

A summary of notes, websites, chats, and files opened today. Gives the assistant awareness of what the user has been working on, enabling it to reference or continue work in those items without being asked.

Cached for 5 minutes per user to avoid repeated database queries within a conversation.

Source: `backend/api/services/agent/prompt/sections.py` (`build_recent_activity_block`)

---

## Budget constraints

The prompt system operates within character budgets to control token costs and stay within model context limits.

| Budget | Limit | Purpose |
|---|---|---|
| Total system prompt | 40,000 chars | Overall ceiling for the assembled system prompt |
| Current Open section | 8,000 chars | Prevents a single large document from dominating the prompt |
| Recent Activity section | 6,000 chars | Limits the activity summary |
| Open file content | Per-file limit | Prevents large files from consuming the budget |
| Attachment content | Per-attachment limit | Same as above |

When a section exceeds its budget, content is truncated. When the total prompt exceeds the overall budget, sections are truncated in priority order (lower-priority sections truncated first).

If the prompt still exceeds the budget after truncation and `strict_system_prompt` is enabled, the request fails with an error.

---

## Template variables

The system prompt template supports dynamic variable substitution. Variables are resolved from user settings, device context, and temporal state.

| Variable | Source | Example |
|---|---|---|
| `{owner}` | User's name or "the user" | "Sean" |
| `{name}` | User's name or "the user" | "Sean" |
| `{current_date}` | Server timestamp in user's timezone | "2026-04-03" |
| `{current_time}` | Server timestamp with timezone label | "14:30 BST" |
| `{homeLocation}` | User settings | "London, UK" |
| `{currentLocationLevels}` | Device location | "Hackney, London, England, UK" |
| `{currentWeather}` | Weather API | "Partly cloudy, 14C" |
| `{tasksSnapshot}` | Tasks AI snapshot | Active tasks summary |

---

## Rules

1. **Never weaken the instruction priority hierarchy.** System messages take precedence over user messages, which take precedence over tool outputs, which take precedence over retrieved content. This is a security boundary.

2. **Never weaken the security constraints.** The rules about not revealing secrets, not following instructions in retrieved content, and not fabricating facts are non-negotiable. No prompt change should soften these.

3. **Identity and soul update on durable evidence only.** The assistant should not rewrite its identity or soul based on a single conversation or one-off request. Changes require repeated preferences, explicit user instructions, or stable patterns.

4. **Defaults must work well for a new user.** A user who has never customised anything should get a good experience from the defaults alone. The default communication style, working relationship, identity, and soul are carefully chosen to be broadly appropriate.

5. **Sections are independent and composable.** Each section should make sense on its own and not depend on specific content in other sections. This allows sections to be omitted, truncated, or reordered without breaking the prompt.

6. **Budget awareness is mandatory.** Any new section or content added to the prompt must account for the character budgets. Large static content should be moved behind tools (like Product Knowledge search) rather than included inline.

7. **Prompt changes are design decisions.** Changing how the assistant behaves, responds, or presents itself is a design decision with the same weight as changing the UI. Prompt changes should be reviewed against the principles in this document.

8. **UK English in all prompt content.** Consistent with the default communication style and the product's voice.

9. **No em dashes in prompt content.** Consistent with the product's voice and content guidelines.

10. **Test prompt changes against real conversations.** Prompt changes can have subtle effects on assistant behaviour. Test changes in real conversation scenarios before committing.

---

## Related docs

- [AI Assistant UI](./ai-assistant-ui) — how the assistant's responses are presented visually
- [Voice and Content](../voice-and-content) — product-wide tone and terminology
- [Onboarding](./onboarding) — the soul calibration flow that initialises identity and soul
- [Subscription](./subscription) — feature gating that affects which capabilities are available
