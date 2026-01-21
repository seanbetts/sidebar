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
pytest                                    # All tests
pytest backend/tests/test_notes_service.py  # Specific file
pytest -k "pin_note"                      # Pattern matching
pytest --cov=api --cov-report=term-missing  # With coverage

# Frontend
npm test                                  # All tests
npm test TaskItem                         # Specific file
npm run coverage                          # With coverage
```

## CI/CD

Tests run automatically on push/PR via GitHub Actions. Coverage reports uploaded to Codecov.

**Tests don't block commits** (only linting/docs do), but they block merge.
