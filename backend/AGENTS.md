# Backend Agent Rules

## Service Layer Pattern

### Structure
```
backend/api/services/{resource}_service.py
```

### Requirements
- All business logic in service classes
- Static methods, first param always `db: Session`
- Return ORM models for domain records. Typed summary helpers may return dataclasses or dict payloads when that is the established service contract.
- Raise custom exceptions (not HTTPException)
- Type hints required

### Common Methods
```python
create_{resource}(db, ...) -> Resource
update_{resource}(db, resource_id, **kwargs) -> Resource
delete_{resource}(db, resource_id) -> bool  # soft delete
get_{resource}(db, resource_id) -> Resource | None
list_{resources}(db, filters...) -> List[Resource]
```

## Database Patterns

### JSONB Updates
```python
from sqlalchemy.orm.attributes import flag_modified

note.metadata_["key"] = value
flag_modified(note, "metadata_")  # REQUIRED
db.commit()
```

### Soft Deletes
```python
resource.deleted_at = datetime.now(timezone.utc)
resource.updated_at = datetime.now(timezone.utc)
db.commit()
```

### Queries Always Exclude Deleted
```python
query = db.query(Note).filter(Note.deleted_at.is_(None))
```

## AI Agent Skills

### Script Pattern
```python
# skills/{skill}/scripts/{action}.py

def {action}_database(params) -> dict:
    """Uses service layer."""
    db = SessionLocal()
    try:
        result = SomeService.method(db, ...)
        return {"success": True, "data": {...}}
    except ServiceError as e:
        return {"success": False, "error": str(e)}
    finally:
        db.close()

# CLI with --database and --json flags
```

### Tool Definition
Add to `backend/api/services/tools/definitions_{domain}.py` and expose it through the current agent tool registry and mapper pipeline.

### SSE Events
Emit UI update events through the current chat SSE pipeline. Start with `backend/api/routers/chat.py` and the active tool event mapping helpers, do not add a parallel streaming path.

## Error Handling

Use custom exceptions from `api/exceptions.py`:
- `NoteNotFoundError(note_id)`
- `ValidationError(field, message)`
- `PermissionDeniedError(resource, action)`

## Testing

- Put tests in the existing backend test layout, usually `backend/tests/api/test_{service}_service.py` or the closest matching module.
- Use `db_session` fixture
- Test happy path + error cases
- Coverage target: 90%+ for services

## Common Mistakes

**DON'T:**
- Put SQL in routers
- Duplicate logic between endpoints and skills
- Hard delete user data
- Forget `flag_modified()` for JSONB
- Return dicts from services (return ORM models)

**DO:**
- Use service layer for all DB operations
- Soft delete with `deleted_at`
- Type hint everything
- Write Google-style docstrings
- Test both success and error paths
