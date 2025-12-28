# Testing Guide

Guide for running tests in the sideBar backend.

## Prerequisites

1. **PostgreSQL test container must be running**
   ```bash
   docker compose -f ../docker-compose.test.yml up -d postgres-test
   ```

2. **Test database must be created**
   ```bash
   ./scripts/setup_test_db.sh
   ```

## Running Tests

### Run all tests
```bash
pytest tests/
```

### Run specific test file
```bash
pytest tests/api/test_notes_service.py
```

### Run tests matching a pattern
```bash
pytest tests/ -k "test_notes"
```

### Run with verbose output
```bash
pytest tests/ -v
```

### Run with coverage (requires pytest-cov)
```bash
pytest tests/ --cov=api --cov-report=term-missing
```

## Test Environment

Tests use a separate PostgreSQL database to ensure isolation from development data.

### Environment Variables

Tests automatically load from `.env.test`:
- `TESTING=1` - Enables test mode
- `DATABASE_URL=postgresql://sidebar:sidebar_dev@localhost:5433/sidebar_test`
- `AUTH_DEV_MODE=true` - Bypass JWT validation in tests
- `ANTHROPIC_API_KEY=test-anthropic-key-12345` - Mock API key

**IMPORTANT**: Never use real secrets in `.env.test`!

### Database Setup

The test database is managed by pytest fixtures:

1. **`test_db_engine`** (session-scoped)
   - Creates database schema once before all tests
   - Drops schema after all tests complete

2. **`test_db`** (function-scoped)
   - Provides clean database session for each test
   - Truncates all tables after each test
   - Ensures test isolation

## Test Structure

```
tests/
├── conftest.py           # Shared fixtures
├── api/                  # API layer tests
│   ├── test_auth.py
│   ├── test_notes_service.py
│   ├── test_websites_service.py
│   └── ...
├── skills/               # Skill-specific tests
└── test_mcp_*.py        # MCP integration tests
```

## Writing Tests

### Service Layer Tests

```python
def test_create_note(test_db):
    """Test creating a note."""
    from api.services.notes_service import NotesService

    # Create note
    note = NotesService.create_note(
        test_db,
        content="Test content",
        title="Test Note"
    )

    # Assert
    assert note.title == "Test Note"
    assert note.content == "Test content"
```

### API Endpoint Tests

```python
def test_list_notes_endpoint(test_client, test_db):
    """Test GET /api/files/notes endpoint."""
    # Create test data
    NotesService.create_note(test_db, content="Test", title="Note 1")

    # Make request
    response = test_client.get(
        "/api/files/notes",
        headers={"Authorization": "Bearer test-bearer-token-12345"}
    )

    # Assert
    assert response.status_code == 200
    assert len(response.json()) == 1
```

## Common Issues

### PostgreSQL not running
```
ERROR: PostgreSQL is not running on localhost:5433
```
**Solution**: Start PostgreSQL with `docker compose -f ../docker-compose.test.yml up -d postgres-test`

### Test database doesn't exist
```
sqlalchemy.exc.OperationalError: database "sidebar_test" does not exist
```
**Solution**: Run `./scripts/setup_test_db.sh`

### Permission denied on test database
```
ERROR: permission denied to create database
```
**Solution**: The postgres user needs createdb permission. Check `docker-compose.test.yml`.

### Tests fail with "No module named 'api'"
```
ModuleNotFoundError: No module named 'api'
```
**Solution**: Run pytest from the backend directory: `cd backend && pytest tests/`

## Continuous Integration

For CI/CD pipelines, ensure:
1. PostgreSQL service is available
2. Test database is created before running tests
3. Environment variables are set correctly

Example GitHub Actions:
```yaml
services:
  postgres:
    image: postgres:16-alpine
    env:
      POSTGRES_USER: sidebar
      POSTGRES_PASSWORD: sidebar_dev
      POSTGRES_DB: postgres
    options: >-
      --health-cmd pg_isready
      --health-interval 10s
      --health-timeout 5s
      --health-retries 5

steps:
  - name: Setup test database
    run: |
      PGPASSWORD=sidebar_dev psql -h localhost -U sidebar -d postgres -c "CREATE DATABASE sidebar_test;"

  - name: Run tests
    run: pytest tests/
    env:
      TESTING: 1
      DATABASE_URL: postgresql://sidebar:sidebar_dev@localhost:5433/sidebar_test
      AUTH_DEV_MODE: true
      ANTHROPIC_API_KEY: test-anthropic-key-12345
```

## Test Data Cleanup

The `test_db` fixture automatically truncates all tables after each test:
- Ensures test isolation
- No need for manual cleanup
- Tests can assume empty database

## Doppler Integration

Tests **DO NOT** require Doppler:
- All secrets are mocked in `.env.test`
- `TESTING=1` disables Doppler lookups
- Tests run locally without network dependencies

Production uses Doppler, tests use local configuration.
