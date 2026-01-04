# Testing Rules

## When to Add Tests

New behavior requires tests. TDD preferred but not enforced.

## What to Test

**Backend (pytest):**
- Service layer methods (90%+ coverage target)
- API endpoints (integration tests)
- Error cases and edge conditions

**Frontend (vitest):**
- Component user interactions (70%+ coverage target)
- Store state updates
- API call handling

## What to Skip

- Generated code
- Third-party wrappers (unless custom logic)
- Trivial pass-through functions

## Tools

**Backend:**
```bash
pytest backend/tests/                          # run all
pytest backend/tests/test_notes_service.py     # specific file
pytest --cov=api --cov-report=term-missing     # coverage
```

**Frontend:**
```bash
npm test                   # run all
npm test TaskItem          # specific file
npm run coverage           # coverage report
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
