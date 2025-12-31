# File Recent Activity Implementation Plan

## Goal

Add recently opened files to the AI assistant's system prompt context, matching the existing pattern used for notes, websites, and conversations.

## Current State

**Models with `last_opened_at` tracking:**
- ✅ `Note` - tracked and included in recent activity
- ✅ `Website` - tracked and included in recent activity
- ✅ `Conversation` - uses `updated_at` for recent activity

**Models without `last_opened_at` tracking:**
- ❌ `IngestedFile` - only has `created_at`, `deleted_at`, `pinned`

## Implementation Steps

### Step 1: Database Migration

Create a new Alembic migration to add the `last_opened_at` column to the `ingested_files` table.

**File**: `/backend/alembic/versions/xxx_add_last_opened_at_to_ingested_files.py`

```python
"""add last_opened_at to ingested_files

Revision ID: xxx
Revises: yyy
Create Date: 2025-01-xx xx:xx:xx.xxxxxx

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'xxx'
down_revision = 'yyy'  # Update with latest revision
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('ingested_files',
        sa.Column('last_opened_at', sa.DateTime(timezone=True), nullable=True)
    )
    op.create_index('idx_ingested_files_last_opened_at', 'ingested_files', ['last_opened_at'])


def downgrade():
    op.drop_index('idx_ingested_files_last_opened_at', table_name='ingested_files')
    op.drop_column('ingested_files', 'last_opened_at')
```

**Run migration:**
```bash
cd backend
alembic revision --autogenerate -m "add last_opened_at to ingested_files"
alembic upgrade head
```

---

### Step 2: Update IngestedFile Model

**File**: `/backend/api/models/file_ingestion.py`

**Current code (lines 11-29):**
```python
class IngestedFile(Base):
    """Canonical metadata for ingested files."""

    __tablename__ = "ingested_files"
    __table_args__ = (
        Index("idx_ingested_files_user_id", "user_id"),
        Index("idx_ingested_files_created_at", "created_at"),
        Index("idx_ingested_files_deleted_at", "deleted_at"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(Text, nullable=False)
    filename_original = Column(Text, nullable=False)
    mime_original = Column(Text, nullable=False)
    size_bytes = Column(BigInteger, nullable=False, default=0)
    sha256 = Column(Text, nullable=True)
    pinned = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)
    deleted_at = Column(DateTime(timezone=True), nullable=True, index=True)
```

**Updated code:**
```python
class IngestedFile(Base):
    """Canonical metadata for ingested files."""

    __tablename__ = "ingested_files"
    __table_args__ = (
        Index("idx_ingested_files_user_id", "user_id"),
        Index("idx_ingested_files_created_at", "created_at"),
        Index("idx_ingested_files_deleted_at", "deleted_at"),
        Index("idx_ingested_files_last_opened_at", "last_opened_at"),  # NEW
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(Text, nullable=False)
    filename_original = Column(Text, nullable=False)
    mime_original = Column(Text, nullable=False)
    size_bytes = Column(BigInteger, nullable=False, default=0)
    sha256 = Column(Text, nullable=True)
    pinned = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)
    last_opened_at = Column(DateTime(timezone=True), nullable=True, index=True)  # NEW
    deleted_at = Column(DateTime(timezone=True), nullable=True, index=True)
```

---

### Step 3: Update Ingestion API to Track File Opens

**File**: `/backend/api/routers/ingestion.py`

Find the `get_file_meta` endpoint and add `last_opened_at` tracking when files are viewed.

**Locate this endpoint:**
```python
@router.get("/{file_id}/meta", response_model=IngestionMetaResponse)
async def get_file_meta(
    file_id: UUID,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
```

**Add after retrieving the file record (before building response):**
```python
    # Update last_opened_at timestamp
    file_record.last_opened_at = datetime.now(timezone.utc)
    db.commit()
```

**Also update the frontend viewer open action** (if not already calling `/meta`):
- Ensure `ingestionViewerStore.open(fileId)` calls the `/meta` endpoint
- This already happens in `/frontend/src/lib/stores/ingestion-viewer.ts` line 20-33

---

### Step 4: Update Prompt Context Service - Add Files Query

**File**: `/backend/api/services/prompt_context_service.py`

**Step 4a: Update import section (add after line 9):**
```python
from api.models.file_ingestion import IngestedFile
```

**Step 4b: Update `_get_recent_activity` method signature (line 224-228):**

**Current:**
```python
@staticmethod
def _get_recent_activity(
    db: Session,
    user_id: str,
    now: datetime,
) -> tuple[list[dict], list[dict], list[dict]]:
    """Fetch recent activity items for prompt context.

    Args:
        db: Database session.
        user_id: Current user ID.
        now: Current timestamp.

    Returns:
        Tuple of (note_items, website_items, conversation_items).
    """
```

**Updated:**
```python
@staticmethod
def _get_recent_activity(
    db: Session,
    user_id: str,
    now: datetime,
) -> tuple[list[dict], list[dict], list[dict], list[dict]]:
    """Fetch recent activity items for prompt context.

    Args:
        db: Database session.
        user_id: Current user ID.
        now: Current timestamp.

    Returns:
        Tuple of (note_items, website_items, conversation_items, file_items).
    """
```

**Step 4c: Add files query (after line 264, before the return statement at line 295):**

```python
        files = (
            db.query(IngestedFile)
            .filter(
                IngestedFile.last_opened_at >= start_of_day,
                IngestedFile.user_id == user_id,
                IngestedFile.deleted_at.is_(None)
            )
            .order_by(IngestedFile.last_opened_at.desc())
            .all()
        )

        file_items = [
            {
                "id": str(file.id),
                "filename": file.filename_original,
                "last_opened_at": file.last_opened_at.isoformat() if file.last_opened_at else None,
                "mime": file.mime_original,
            }
            for file in files
        ]

        return note_items, website_items, conversation_items, file_items
```

**Step 4d: Update the call to `_get_recent_activity` (lines 98-105):**

**Current:**
```python
note_items, website_items, conversation_items = PromptContextService._get_recent_activity(
    db, user_id, timestamp
)
recent_activity_block = build_recent_activity_block(
    note_items,
    website_items,
    conversation_items,
)
```

**Updated:**
```python
note_items, website_items, conversation_items, file_items = PromptContextService._get_recent_activity(
    db, user_id, timestamp
)
recent_activity_block = build_recent_activity_block(
    note_items,
    website_items,
    conversation_items,
    file_items,
)
```

---

### Step 5: Update Recent Activity Block Builder

**File**: `/backend/api/prompts.py`

**Step 5a: Update function signature (line 331-335):**

**Current:**
```python
def build_recent_activity_block(
    notes: list[dict[str, Any]],
    websites: list[dict[str, Any]],
    conversations: list[dict[str, Any]],
) -> str:
    """Render the recent activity block for prompts.

    Args:
        notes: Recent note items.
        websites: Recent website items.
        conversations: Recent conversation items.

    Returns:
        Rendered recent activity block string.
    """
```

**Updated:**
```python
def build_recent_activity_block(
    notes: list[dict[str, Any]],
    websites: list[dict[str, Any]],
    conversations: list[dict[str, Any]],
    files: list[dict[str, Any]],
) -> str:
    """Render the recent activity block for prompts.

    Args:
        notes: Recent note items.
        websites: Recent website items.
        conversations: Recent conversation items.
        files: Recent file items.

    Returns:
        Rendered recent activity block string.
    """
```

**Step 5b: Add files block (after line 379, before the empty check at line 381):**

```python
    if files:
        if lines:
            lines.append("")
        lines.append(RECENT_ACTIVITY_FILES_HEADER)
        for file in files:
            mime = f", type: {file['mime']}" if file.get("mime") else ""
            lines.append(
                f"- {file['filename']} (last_opened_at: {file['last_opened_at']}, id: {file['id']}{mime})"
            )
```

**Step 5c: Add constant at top of file (after line 42):**

Find where other constants are loaded (around line 42):
```python
RECENT_ACTIVITY_NOTES_HEADER = _PROMPT_CONFIG["recent_activity_notes_header"]
RECENT_ACTIVITY_WEBSITES_HEADER = _PROMPT_CONFIG["recent_activity_websites_header"]
RECENT_ACTIVITY_CHATS_HEADER = _PROMPT_CONFIG["recent_activity_chats_header"]
RECENT_ACTIVITY_FILES_HEADER = _PROMPT_CONFIG["recent_activity_files_header"]  # NEW
```

---

### Step 6: Update Prompts Configuration

**File**: `/backend/api/config/prompts.yaml`

**Add after line 131:**

**Current:**
```yaml
recent_activity_notes_header: "Notes opened today:"
recent_activity_websites_header: "Websites opened today:"
recent_activity_chats_header: "Chats active today:"
```

**Updated:**
```yaml
recent_activity_notes_header: "Notes opened today:"
recent_activity_websites_header: "Websites opened today:"
recent_activity_chats_header: "Chats active today:"
recent_activity_files_header: "Files opened today:"
```

---

### Step 7: Update Tests

**File**: `/backend/tests/api/test_prompt_context_service.py`

Update any tests for `_get_recent_activity` to expect 4-tuple instead of 3-tuple:

```python
def test_get_recent_activity():
    # ... test setup ...

    note_items, website_items, conversation_items, file_items = PromptContextService._get_recent_activity(
        db, user_id, now
    )

    # Add assertions for file_items
    assert isinstance(file_items, list)
```

**File**: `/backend/tests/api/test_prompts.py`

Update tests for `build_recent_activity_block` to include files parameter:

```python
def test_build_recent_activity_block_with_files():
    files = [
        {
            "id": "file-123",
            "filename": "document.pdf",
            "last_opened_at": "2025-01-01T10:00:00",
            "mime": "application/pdf"
        }
    ]

    result = build_recent_activity_block([], [], [], files)

    assert "Files opened today:" in result
    assert "document.pdf" in result
    assert "file-123" in result
```

---

## Testing Checklist

### Manual Testing

1. **Upload a file** through the UI
2. **Open the file** by clicking it in the Files panel
3. **Start a new chat** conversation
4. **Ask the AI** "What files have I opened today?"
5. **Verify** the AI mentions the file you opened

### Database Verification

```sql
-- Check that last_opened_at column exists
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'ingested_files'
AND column_name = 'last_opened_at';

-- Check that index exists
SELECT indexname
FROM pg_indexes
WHERE tablename = 'ingested_files'
AND indexname = 'idx_ingested_files_last_opened_at';

-- Verify data is being tracked
SELECT id, filename_original, last_opened_at
FROM ingested_files
WHERE last_opened_at IS NOT NULL
ORDER BY last_opened_at DESC
LIMIT 5;
```

### Unit Test Verification

```bash
cd backend
pytest tests/api/test_prompt_context_service.py -v
pytest tests/api/test_prompts.py -v
```

---

## Expected Prompt Output

After implementation, when a user opens files during the day, the system prompt should include:

```
<recent_activity>
Notes opened today:
- Project Planning (last_opened_at: 2025-01-01T09:30:00, id: abc-123, folder: Work)

Websites opened today:
- FastAPI Documentation (last_opened_at: 2025-01-01T10:15:00, id: def-456, domain: fastapi.tiangolo.com, url: https://fastapi.tiangolo.com/tutorial/)

Files opened today:
- quarterly-report.pdf (last_opened_at: 2025-01-01T11:00:00, id: ghi-789, type: application/pdf)
- meeting-notes.docx (last_opened_at: 2025-01-01T11:30:00, id: jkl-012, type: application/vnd.openxmlformats-officedocument.wordprocessingml.document)

Chats active today:
- Discuss Q4 Goals (last_opened_at: 2025-01-01T14:00:00, id: mno-345, messages: 12)
</recent_activity>
```

---

## Files to Modify

Summary of all files that need changes:

1. **New Migration**: `/backend/alembic/versions/xxx_add_last_opened_at_to_ingested_files.py`
2. **Model**: `/backend/api/models/file_ingestion.py`
3. **API Router**: `/backend/api/routers/ingestion.py`
4. **Service**: `/backend/api/services/prompt_context_service.py`
5. **Prompts**: `/backend/api/prompts.py`
6. **Config**: `/backend/api/config/prompts.yaml`
7. **Tests**: `/backend/tests/api/test_prompt_context_service.py`
8. **Tests**: `/backend/tests/api/test_prompts.py`

---

## Success Criteria

✅ Migration runs successfully without errors
✅ `last_opened_at` column exists in `ingested_files` table with index
✅ Opening a file in the UI updates `last_opened_at` timestamp
✅ Files opened today appear in recent activity prompt context
✅ Files are formatted consistently with notes/websites (filename, timestamp, id, type)
✅ All existing tests pass
✅ New tests for file recent activity pass
✅ AI assistant can reference recently opened files in responses

---

## Rollback Plan

If issues occur:

1. **Revert migration**:
   ```bash
   cd backend
   alembic downgrade -1
   ```

2. **Revert code changes** using git:
   ```bash
   git checkout HEAD -- backend/api/models/file_ingestion.py
   git checkout HEAD -- backend/api/routers/ingestion.py
   git checkout HEAD -- backend/api/services/prompt_context_service.py
   git checkout HEAD -- backend/api/prompts.py
   git checkout HEAD -- backend/api/config/prompts.yaml
   ```

3. **Restart backend** to clear cached prompt config

---

## Implementation Notes

- The pattern follows existing `last_opened_at` implementation for notes and websites
- Files use `last_opened_at >= start_of_day` filter (same as notes/websites)
- Deleted files are excluded via `deleted_at.is_(None)` filter
- The prompt shows filename instead of title (files don't have separate titles)
- MIME type is included to help AI understand file context
- Frontend already calls `/meta` endpoint when viewing files, so tracking happens automatically
