# Testing Rules

## When to Add Tests

New behavior requires tests.

For feature work and bug fixes, follow the active superpowers TDD workflow unless the user explicitly instructs otherwise. For documentation-only changes, add tests only if behavior changes.

## What to Test

**Backend (pytest):**
- Service layer methods (90%+ coverage target)
- API endpoints (integration tests)
- Error cases and edge conditions

**Frontend (vitest):**
- Component user interactions (70%+ coverage target)
- Store state updates (80%+ coverage target)
- API call handling

## What to Skip

- Generated code
- Third-party wrappers (unless custom logic)
- Trivial pass-through functions

## Tools

**Backend:**
```bash
(cd backend && pytest tests/)                                      # run all
(cd backend && pytest tests/api/test_notes_service.py)             # specific file
(cd backend && pytest --cov=api --cov-report=term-missing tests/)  # coverage
```

**Frontend:**
```bash
(cd frontend && npm test)                                              # run all
(cd frontend && npm test -- src/tests/components/files-panel.test.ts)  # specific file
(cd frontend && npm run coverage)                                      # coverage report
```

## Test Structure

**Backend:**
```
backend/tests/
├── test_{service}_service.py
├── test_{router}_router.py
└── fixtures/
```

**Frontend:**
```
frontend/src/tests/
├── components/
├── stores/
└── utils/
```

## Fixtures

Use `db_session` fixture for database tests:
```python
def test_create_note(db_session):
    note = NotesService.create_note(db_session, "# Test")
    assert note.id is not None
```

## Coverage

Tests run in CI. Coverage reported to Codecov.

Target:
- Backend services: 90%+
- Frontend components/stores: 70%+
