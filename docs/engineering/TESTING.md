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

# iOS - Logic tests (fast, no simulator, recommended for TDD)
xcodebuild test -project ios/sideBar/sideBar.xcodeproj \
  -scheme sideBarLogicHost -testPlan AppleFast \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=

# iOS - Coverage lane (manual, no simulator)
xcodebuild test -project ios/sideBar/sideBar.xcodeproj \
  -scheme sideBarLogicHost -testPlan AppleCoverage \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -enableCodeCoverage YES \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=

# iOS - Full suite (needs iOS simulator)
xcodebuild test -project ios/sideBar/sideBar.xcodeproj \
  -scheme sideBar -testPlan AppleStateful \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# iOS - UI smoke tests
xcodebuild test -project ios/sideBar/sideBar.xcodeproj \
  -scheme sideBarUI -testPlan AppleUI \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# iOS - Extension tests
xcodebuild test -project ios/sideBar/sideBar.xcodeproj \
  -scheme sideBarExtensions -testPlan AppleExtensions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The default backend lane targets local Postgres on `localhost:5433/sidebar_test`.
`setup_test_db.sh` recreates the DB and applies Alembic migrations, and preflight now also checks schema baseline/stamping consistency.
Hosted Supabase runs require `USE_SUPABASE_TEST_DB=1` plus dedicated non-placeholder test credentials.
Hosted credentials are read from `backend/.env.test` for test runs.
If `.env.test` keeps `SUPABASE_POSTGRES_PSWD` as a placeholder, Doppler-backed runs can hydrate the real value at runtime via `DOPPLER_TOKEN`.
`SUPABASE_APP_PSWD` is only a legacy fallback and is not required in `backend/.env.test`.
The preflight command validates lane configuration and runs `SELECT 1` before pytest.

### iOS Test Plans

| Plan | Scheme | What it tests | Simulator needed? |
|------|--------|---------------|-------------------|
| AppleFast | sideBarLogicHost | Pure logic, parsers, formatters, state machines, API mocks | No (runs on macOS) |
| AppleStateful | sideBar | Mounted views, app environment, persistence, integration | Yes |
| AppleUI | sideBarUI | End-to-end smoke (login, messaging, notes) | Yes |
| AppleExtensions | sideBarExtensions | Share sheet, widgets, Safari extension | Yes |

Current lane split for the website-save checkpoint:

- `sideBarLogicTests/WebsitesViewModelTests` runs in `AppleFast`.
- `sideBarTests/WebsitesStoreTests` stays in `AppleStateful`.
- `sideBarTests/AppEnvironmentDeepLinkTests` stays in `AppleStateful`.
- `ShareExtensionTests/ShareExtensionCoverageTests` stays in `AppleExtensions`.

Use separate commands per lane instead of mixing them under `sideBarLogicHost`:

```bash
# Logic lane
xcodebuild test -project ios/sideBar/sideBar.xcodeproj \
  -scheme sideBarLogicHost -testPlan AppleFast \
  -destination 'platform=macOS' \
  -only-testing:sideBarLogicTests/WebsitesViewModelTests

# Stateful lane
xcodebuild test -project ios/sideBar/sideBar.xcodeproj \
  -scheme sideBar -testPlan AppleStateful \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:sideBarTests/WebsitesStoreTests \
  -only-testing:sideBarTests/AppEnvironmentDeepLinkTests

# Extension lane
xcodebuild test -project ios/sideBar/sideBar.xcodeproj \
  -scheme sideBarExtensions -testPlan AppleExtensions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ShareExtensionTests/ShareExtensionCoverageTests
```

### CI Behavior

| Branch | What runs | Blocking? |
|--------|-----------|-----------|
| `dev` | SwiftLint + doc comments + AppleFast logic tests (macOS, no simulator) | Yes |
| `main` | AppleFast logic tests (macOS) + AppleUI + AppleExtensions (iOS simulator) | Yes |

**Pre-push:** Lint checks only (SwiftLint, doc comments, linear history). No test execution.

## CI/CD

Backend/frontend tests run automatically on push/PR via GitHub Actions.

iOS CI runs on a self-hosted Mac runner:
- `dev`: logic tests on macOS destination (no simulator, blocks on failure)
- `main`: logic tests on macOS + UI/extension tests on iOS simulator (blocks on failure to prevent broken Xcode Cloud builds)
