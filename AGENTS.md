# sideBar Agent Instructions

## Purpose

Full-stack AI assistant platform (SvelteKit + FastAPI). Shared service layer between UI and AI agent operations.

## Quick Start

```bash
docker compose up -d                 # dev
pytest backend/tests/                # backend tests
npm test                             # frontend tests (in frontend/)
ruff check backend/ && npm run lint  # lint
```

## Constraints

**Service layer owns business logic**
- All database access through `backend/api/services/`
- Endpoints and AI skills call services, never duplicate logic

**Soft deletes only**
- Set `deleted_at` timestamp, never hard delete user data

**Real-time updates**
- AI tool execution emits SSE events for UI reactivity
- Pattern: `backend/api/services/claude_streaming.py`

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
- Do not delete or rename unexpected files/behaviour. Stop and ask

## Anti-Patterns

- Business logic in API routes
- Database access outside service layer
- Duplicating logic between endpoints and skills
- Hard deletes
- Committing debugging artifacts (console.log, debugger, print)
- Files exceeding size limits

## Testing

Write tests for new behavior. Prefer a failing test first when practical.

**Tools:** pytest (backend), vitest (frontend)
**Coverage targets:** 90% services, 70% components/stores
**Details:** `tests/AGENTS.md`

## Definition of Done

- [ ] Update or add tests for any behaviour change (prefer failing test first when practical)
- [ ] Tests pass (pytest, vitest)
- [ ] Linting passes (ruff, eslint)
- [ ] Type checking passes (mypy, tsc)
- [ ] Docstrings present (Python 80%+, TypeScript 90%+)
- [ ] File size within limits
- [ ] No console.log, debugger, or print() statements

## When to Ask

**Stop and ask:**
- Breaking API or database schema changes
- Deleting unexpected files
- Security configuration
- Ambiguous requirements

## Autonomy and check-ins
- Work in multi-step batches. Do not stop after each small change.
- Only ask me a question when blocked by:
  - a missing requirement that changes behaviour
  - a risky choice with multiple reasonable options
  - missing secrets, credentials, or access
- Otherwise, make reasonable assumptions, note them briefly in the final summary, and continue.
- Prefer: plan -> implement -> run checks -> fix -> final summary.
- Prefer evidence over assumptions: inspect logs, run curls, and write small one-off scripts to confirm hypotheses when debugging.
- If unsure, read more code in the relevant module before asking. If still blocked, ask with 2–3 short options.
- Do not pause to check in after intermediate steps or partial progress.
- For larger tasks, write a plan to docs/plans/<yyyy-mm-dd>-<slug>.md, keep it short, and delete it when complete.

**Decide autonomously:**
- Implementation details
- Refactoring within limits
- Tests and documentation

## Gotchas

- **Supabase**: Must use connection pooler (see DATABASE_URL in .env.example)

---

Backend: `backend/AGENTS.md` | Frontend: `frontend/AGENTS.md` | Testing: `tests/AGENTS.md`
