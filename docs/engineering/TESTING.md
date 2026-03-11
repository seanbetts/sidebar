---
title: "Testing Philosophy"
description: "Testing approach, tools, and expectations for sideBar."
---

# Testing Philosophy

## General Approach

**Prefer TDD when practical:**
1. Write failing test
2. Write minimum code to pass
3. Refactor
4. Verify test still passes

**When not TDD:**
- Exploratory work
- Spike solutions
- UI layout/styling

But always add tests before committing.

## Backend (pytest)

### Test Structure
```
backend/tests/
├── test_{service}_service.py      # Service layer tests
├── test_{router}_router.py        # Endpoint integration tests
└── fixtures/                       # Shared fixtures
```

### Coverage Target
- **Services**: 90%+ (business logic is critical)
- **Routers**: 80%+ (integration tests)
- **Models**: Light coverage (focus on custom methods)

### Fixtures
Use `db_session` fixture for database tests:
```python
def test_create_note(db_session):
    note = NotesService.create_note(db_session, "# Test")
    assert note.id is not None
```

### What to Test
- Happy path
- Error cases (not found, validation failures)
- Edge cases (empty strings, special characters)
- Business rules enforcement

## Frontend (Vitest)

### Test Structure
```
frontend/src/tests/
├── components/          # Component tests
├── stores/              # Store tests
└── utils/               # Utility tests
```

### Coverage Target
- **Components**: 70%+ (user interactions)
- **Stores**: 80%+ (state management is critical)
- **Utils**: 90%+ (pure functions, easy to test)

### Testing Library
Use `@testing-library/svelte` with user-centric queries:
```typescript
import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';

it('should complete task when clicked', async () => {
  const user = userEvent.setup();
  render(TaskItem, { props: { task } });

  await user.click(screen.getByRole('checkbox'));

  expect(mockComplete).toHaveBeenCalled();
});
```

### What to Test
- User interactions (clicks, typing, etc.)
- State updates
- API calls (mock with vitest)
- Error handling
- Loading states

## Integration Tests

Test full flows across layers:
- Backend: API endpoint → service → database
- Frontend: User action → store update → API call → UI update

## API Smoke Tests (Local Only)

We keep a lightweight API smoke suite to catch route regressions (e.g., `/api/v1` paths).
It runs only when explicitly enabled, so it won't break CI.

```bash
# Run locally against a running app on http://localhost:3000
RUN_API_SMOKE=1 npm test -- src/tests/flows/api-smoke.test.ts

# Optional: include the YouTube file endpoint (may return validation errors)
RUN_API_SMOKE=1 RUN_API_SMOKE_YOUTUBE=1 npm test -- src/tests/flows/api-smoke.test.ts
```

## Don't Over-Test

**Skip tests for:**
- Generated code
- Third-party library wrappers (unless custom logic)
- Pure pass-through functions
- Trivial getters/setters

**Focus tests on:**
- Business logic
- User-facing behavior
- Error handling
- Edge cases

## Test Naming

Be descriptive:
```python
# Good
def test_pin_note_raises_error_when_note_not_found():
    ...

# Bad
def test_pin():
    ...
```

## Running Tests

```bash
# Backend
./backend/scripts/setup_test_db.sh
cd backend
UV_NATIVE_TLS=1 uv run python scripts/check_test_db_connectivity.py
DATABASE_URL=postgresql://sidebar:sidebar_dev@localhost:5433/sidebar_test UV_NATIVE_TLS=1 uv run pytest -q -rs
UV_NATIVE_TLS=1 uv run pytest tests/api/test_notes_service.py  # Specific file
UV_NATIVE_TLS=1 uv run pytest -k "pin_note"                # Pattern matching
UV_NATIVE_TLS=1 uv run pytest --cov=api --cov-report=term-missing  # With coverage

# Hosted Supabase integration lane (explicit opt-in)
USE_SUPABASE_TEST_DB=1 UV_NATIVE_TLS=1 uv run python scripts/check_test_db_connectivity.py
USE_SUPABASE_TEST_DB=1 UV_NATIVE_TLS=1 uv run pytest -q -rs

# Frontend
npm test                                  # All tests
npm test TaskItem                         # Specific file
npm run coverage                          # With coverage

# iOS
./scripts/test-ios.sh                     # default fast macOS AppleFast lane
IOS_DESTINATION='platform=iOS Simulator,name=iPhone 15 Pro' ./scripts/test-ios.sh
IOS_SCHEME=sideBarUI ./scripts/test-ios.sh                         # default curated UI smoke lane
IOS_SCHEME=sideBarUI IOS_UI_SMOKE_ONLY=NO ./scripts/test-ios.sh    # broader UI regression lane
IOS_SCHEME=sideBarExtensions ./scripts/test-ios.sh                 # extension lane

# Deterministic CLI verification for the fast/default iOS lane
xcodebuild -project ios/sideBar/sideBar.xcodeproj -scheme sideBar \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test

# Explicit UI and extension lanes
xcodebuild -project ios/sideBar/sideBar.xcodeproj -scheme sideBarUI \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test
xcodebuild -project ios/sideBar/sideBar.xcodeproj -scheme sideBarExtensions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test

# Optional local retry mode for transient simulator/runtime flake triage
xcodebuild -project ios/sideBar/sideBar.xcodeproj -scheme sideBar \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -retry-tests-on-failure -test-iterations 3 test
```

The default backend lane targets local Postgres on `localhost:5433/sidebar_test`.
`setup_test_db.sh` recreates the DB and applies Alembic migrations, and preflight now also checks schema baseline/stamping consistency.
Hosted Supabase runs require `USE_SUPABASE_TEST_DB=1` plus dedicated non-placeholder test credentials.
Hosted credentials are read from `backend/.env.test` for test runs.
If `.env.test` keeps `SUPABASE_POSTGRES_PSWD` as a placeholder, Doppler-backed runs can hydrate the real value at runtime via `DOPPLER_TOKEN`.
`SUPABASE_APP_PSWD` is only a legacy fallback and is not required in `backend/.env.test`.
The preflight command validates lane configuration and runs `SELECT 1` before pytest.

### iOS Test Stability

- Parallel full-suite execution can produce intermittent simulator/runtime crashes.
- For release verification and CI-like confidence, prefer serial execution:
  - `-parallel-testing-enabled NO`
- Use retry mode for local triage only; do not treat it as equivalent to a stable serial pass.

### Apple Lane Routing

| Lane | Scheme / Plan | Default scope | Blocking status | When to run |
| --- | --- | --- | --- | --- |
| Fast | `sideBarMacTests` / `AppleFast` | Deterministic unit and component coverage | Required | `push` to `dev`, local default |
| Stateful | `sideBar` / `AppleStateful` | Persistence, globals, cross-store integration | Informational | Manual regression when touching stateful app flows |
| UI smoke | `sideBarUI` / `AppleUI` | Curated smoke coverage with one real login and seeded auth for the rest | Informational | Manual smoke checks, release verification, local UI checks |
| Extensions | `sideBarExtensions` / `AppleExtensions` | Share sheet, widgets, Safari extension surfaces | Informational | Manual regression when touching extension code |

### Apple UI Smoke Policy

- `IOS_SCHEME=sideBarUI ./scripts/test-ios.sh` now defaults to the curated smoke set.
- The default smoke set keeps one interactive login proof, then boots the rest of the UI checks from seeded authenticated state.
- To run broader UI coverage, use `IOS_UI_SMOKE_ONLY=NO` or pass explicit `IOS_ONLY_TESTING=...`.
- Launch screenshot coverage is no longer part of the default UI smoke path.
- GitHub Actions `workflow_dispatch` runs of the `ui` lane require these repository secrets:
  `SIDEBAR_UI_TEST_EMAIL`, `SIDEBAR_UI_TEST_PASSWORD`, `API_BASE_URL`,
  `SUPABASE_URL`, and `SUPABASE_ANON_KEY`.

### Quarantine Ownership

- A test may stay in a non-required lane, but it must not return to `AppleFast` until it is deterministic under serial local reruns.
- Any quarantined Apple test needs three things documented in the owning change: failure mode, owning surface, and the lane where it still runs.
- If a flaky test blocks `AppleFast`, move it out of the required lane first, then fix the harness; do not leave intermittent failures in pre-push.
- The engineer touching the affected Apple surface owns the quarantine entry until the test is restored or deleted.

## CI/CD

Backend/frontend tests run automatically on push/PR via GitHub Actions. Coverage reports uploaded to Codecov.

Xcode Cloud and any broader Apple coverage jobs should run the explicit lane schemes:
- `sideBar` for the fast/default unit lane
- `sideBarUI` for UI coverage
- `sideBarExtensions` for extension coverage

**iOS tests run on commit when `ios/` changes** via pre-commit; other tests don't block commits, but they block merge.
