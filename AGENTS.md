# sideBar Agent Instructions

## Purpose

Full-stack AI assistant platform (SvelteKit + FastAPI). Shared service layer between UI and AI agent operations.

## Instruction Precedence

- Direct user instructions override everything else.
- Repo `AGENTS.md` files define repo-specific architecture, testing targets, and safety constraints.
- Superpowers skills remain authoritative for process discipline, especially brainstorming, planning, TDD, and verification.
- Do not use this file to justify skipping a required superpowers step. Use it to adapt that process to this repo.

## Quick Start

```bash
docker compose up -d                 # dev
(cd backend && pytest tests/)        # backend tests
(cd frontend && npm test)            # frontend tests
(cd backend && ruff check api workers && mypy api)   # backend lint + types
(cd frontend && npm run lint && npm run check)       # frontend lint + types
```

## Constraints

**Service layer owns business logic**
- All database access through `backend/api/services/`
- Endpoints and AI skills call services, never duplicate logic

**Soft deletes only**
- Set `deleted_at` timestamp, never hard delete user data

**Real-time updates**
- AI tool execution emits SSE events for UI reactivity
- Pattern: use the current chat SSE pipeline centered on `backend/api/routers/chat.py`

**File size limits** (pre-commit enforced)
- Backend: 600 LOC (services), 500 LOC (routers)
- Frontend: 600 LOC (components/stores)

**JSONB updates**
- Must call `flag_modified(model, "field")` or changes won't persist

**Naming conventions**
- Error messages: "Invalid {resource} ID" (capitalized ID, no underscores)
- Python identifiers: snake_case for variables/functions, PascalCase for classes
- TypeScript identifiers: camelCase for variables/functions, PascalCase for components/types

**Other constraints**
- Fix root causes. Avoid band-aids that hide symptoms
- Do not delete or rename unexpected files/behaviour. Stop and ask if deletion/rename is required.
- If unexpected modified/untracked files exist, default to option 1: stage and commit only task-related files, leave other files untouched, and continue without asking.
- Do not bypass git hooks (`--no-verify`) unless the user explicitly asks for that in the current request.
- If a push is blocked by hooks/checks: report the exact failure, fix it, rerun checks, and push normally only after passing.

## Anti-Patterns

- Business logic in API routes
- Database access outside service layer
- Duplicating logic between endpoints and skills
- Hard deletes
- Committing debugging artifacts (console.log, debugger, print)
- Files exceeding size limits

## Testing

Write tests for new behavior.

For feature work and bug fixes, follow the active superpowers TDD workflow unless the user explicitly instructs otherwise. For documentation-only or configuration-only changes, add tests when behavior changes or coverage would otherwise regress.

### Apple test taxonomy

Use one Apple test taxonomy across the shared iOS/macOS app. Do not create feature-specific testing rules for Notes, Files, Chat, Tasks, Websites, Skills, or other surfaces.

- `Logic`: deterministic shared-code tests, this is the default layer for new Apple coverage
- `Surface`: mounted views, app-environment wiring, persistence, platform-hosted behavior, and broader integration coverage
- `UI Smoke`: tiny end-to-end app checks only

Branch policy for the Apple test taxonomy:

- `dev` should run `Logic`
- `main` should run `Logic`, `Surface`, and `UI Smoke`

When adding or changing Apple coverage, choose the lowest appropriate Apple test layer first.
- default new Apple tests to `logic`
- choose `surface` only when the logic layer cannot prove the behavior
- choose `ui_smoke` only for true end-to-end coverage
- layer repo-local Apple testing rules on top of third-party skills, do not edit the third-party skills themselves

Apple support files and helpers should be kept separate from test cases conceptually, even when they live in test directories. Update the committed taxonomy manifest when moving or adding Apple test/support files.

**Tools:** pytest (backend), vitest (frontend)
**Coverage targets:** 90% services, 70% components/stores
**Details:** `tests/AGENTS.md`

## Product Documentation

User-facing product docs live in `docs/product/` and are deployed via Mintlify to docs.trysidebar.ai.

**Structure:**
- `manual/` — long-form user guidance (introduction, getting started, per-feature pages)
- `faq/` — short answer-oriented content (per-feature + general, privacy)
- `skills/` — one page per skill (required, standard)
- `skills/store/` — one page per store skill
- `snippets/remediation/` — reusable remediation copy

**When to update docs:**
- Adding a new feature or skill: add the corresponding manual, FAQ, and/or skill page
- Changing existing behaviour: update the affected pages to match
- Adding or removing a skill: update `docs/product/docs.json` navigation
- Changing skill capabilities: update the skill page's Actions table and description

**Frontmatter:** All product docs require `title`, `summary`, `tags`, `audience`, `surfaces`. Skill docs also require `skill_id` matching the runtime identifier from `backend/api/services/tools/skill_metadata.py`.

**Writing style:**
- No em dashes (use a comma, colon, or restructure the sentence)
- Skill pages use a table for the Actions section (`| Action | Description |`)
- Keep answers direct and concise

## Definition of Done

- [ ] Update or add tests for any behaviour change, following the active TDD workflow when applicable
- [ ] Tests pass (pytest, vitest)
- [ ] Linting passes (`cd backend && ruff check api workers`, `cd frontend && npm run lint`)
- [ ] Type checking passes (`cd backend && mypy api`, `cd frontend && npm run check`)
- [ ] Docstrings present (Python 80%+, TypeScript 90%+)
- [ ] File size within limits
- [ ] No console.log, debugger, or print() statements
- [ ] Product docs updated if user-facing behaviour changed (`docs/product/`)

## When to Ask

**Stop and ask:**
- Breaking API or database schema changes
- Deleting or renaming unexpected files
- Security configuration
- Ambiguous requirements

## Autonomy and check-ins
- Work in multi-step batches. Do not stop after each small change.
- For tasks that trigger superpowers process skills, follow their required sequence. In practice that usually means: approved design, written plan, implementation, verification.
- Planning vocabulary for this repo:
  - `Task` is the execution unit in an implementation plan. Implementers and subagents pick up one task at a time.
  - `Step` is a checkbox-sized action inside a task, usually the TDD loop or a verification action.
  - `Phase` is optional rollout or reporting language only. Use it to describe broad sequencing or status when helpful, but do not use phases as the unit of execution.
  - If a plan uses phases, every executable item should still be written as tasks with steps. Do not treat phase names and task names as interchangeable.
- Only ask me a question when blocked by:
  - a missing requirement that changes behaviour
  - a risky choice with multiple reasonable options
  - missing secrets, credentials, or access
- Otherwise, make reasonable assumptions, note them briefly in the final summary, and continue.
- Prefer: follow the required process skill, then implement, run checks, fix, and summarize.
- Prefer evidence over assumptions: inspect logs, run curls, and write small one-off scripts to confirm hypotheses when debugging.
- If unsure, read more code in the relevant module before asking. If still blocked, ask one concise plain-text question.
- Do not pause to check in after intermediate steps or partial progress.
- When a planning skill requires a spec or plan document, use the location that skill requires unless the user says otherwise.

**Decide autonomously:**
- Implementation details
- Refactoring within limits
- Tests and documentation

## Continuation And Minor Tweaks

Superpowers process skills remain the default for new features, new behavior, ambiguous changes, and work that needs fresh design or planning.

Do not restart the full Superpowers workflow for continuation feedback on work already in progress.

Treat the following as continuation work by default:
- regression fixes in recently completed or in-flight work
- user feedback on an existing spec, plan, branch, or implementation
- localized UI polish, including spacing, typography, sizing, alignment, copy, section emphasis, visual hierarchy, and layout cleanup
- small binding, display, or persistence fixes within the already-approved feature scope

For continuation work:
- continue using the existing approved spec or plan when one exists
- update the existing spec or plan only if needed to keep it accurate
- do not create a new spec or a new plan document unless scope materially expands
- when updating an existing plan, preserve the repo vocabulary above: phases are optional status buckets, tasks are the executable units, and steps are the checkbox actions
- do not invoke brainstorming for localized polish or corrective changes that stay within the approved scope
- do not invoke writing-plans solely because the user is giving follow-up tweaks or regression feedback
- still perform implementation, testing, and verification proportional to the change

Start a new Superpowers design or planning cycle only when the request:
- adds net-new functionality
- changes workflow semantics or product behavior beyond the approved scope
- introduces meaningful architectural, data-flow, or API decisions
- is ambiguous enough that design tradeoffs need explicit review

## Sentry Access

When debugging production or pre-release Apple crashes, prefer checking real Sentry issues and events instead of inferring from local logs alone.

Load local Sentry auth from `.env.local`:

```bash
set -a && source .env.local && set +a
```

Verify access:

```bash
sentry-cli info
```

For direct API checks when `sentry-cli` subcommands are limited:

```bash
curl -sS -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
  "https://sentry.io/api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/issues/"
```

Useful defaults:
- required local env vars: `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`
- Apple app release format: `bundleIdentifier@version+build`
- never commit tokens, DSNs, or copied secret values into the repo or docs

## Gotchas

- **Supabase**: Must use connection pooler (see DATABASE_URL in .env.example)

---

Backend: `backend/AGENTS.md` | Frontend: `frontend/AGENTS.md` | Testing: `tests/AGENTS.md`
