# fs Skill Migration to Ingestion System

## Goal

Consolidate file storage by migrating the `fs` skill from the `file_objects` table to the `ingested_files` table and ingestion pipeline. This eliminates dual storage systems and ensures all files (AI-created and user-uploaded) are handled uniformly.

## Current Architecture

### Three Storage Systems

1. **Notes** (`notes` table)
   - PostgreSQL-only storage for markdown content
   - Lightweight, fast, searchable
   - **Decision: Keep as-is** (notes aren't "files")

2. **Workspace Files** (`file_objects` table) - **TO BE ELIMINATED**
   - Simple files created by AI via `fs` skill
   - R2 paths: `users/{user_id}/path/to/file.txt`
   - Direct storage, no processing pipeline
   - **Problem**: Separate from user-uploaded files

3. **Ingested Files** (`ingested_files` table) - **TARGET SYSTEM**
   - User uploads through UI
   - Processing pipeline with derivatives
   - R2 paths: `files/{file_id}/derivatives/*`
   - **Solution**: Migrate fs skill to use this

## Benefits of Migration

### Unified Architecture
- ✅ Single file storage mechanism
- ✅ All files visible to both user and AI
- ✅ Consistent processing pipeline
- ✅ Eliminates `file_objects` table complexity

### Enhanced Capabilities
- ✅ Automatic `ai.md` generation for all files
- ✅ Thumbnails for supported formats
- ✅ File metadata tracking (MIME, category, size)
- ✅ Processing status visibility
- ✅ Derivative management

### Better AI Context
- ✅ AI sees user-uploaded files
- ✅ User sees AI-created files
- ✅ Consistent file access patterns
- ✅ Better prompt context (all files in recent activity)

## Migration Strategy

### Phase 1: Add Fast-Track Processing for Simple Files

Text files, markdown, JSON don't need heavy processing. Create a "simple" mode that bypasses unnecessary stages.

**Update**: `/backend/workers/ingestion_worker.py`

Add fast-track logic:
```python
def should_fast_track(mime: str, extension: str) -> bool:
    """Determine if file can skip processing stages."""
    simple_types = {
        'text/plain',
        'text/markdown',
        'application/json',
        'text/csv',
        'application/javascript',
        'text/html',
        'text/css',
    }
    return mime in simple_types

def process_simple_file(file_id: UUID, content: bytes, mime: str):
    """Fast-track processing for text files."""
    # Stage 1: Store original as derivative
    storage_key = f"files/{file_id}/original"
    storage.put_object(storage_key, content, mime)

    # Stage 2: Create ai.md with minimal metadata
    text = content.decode('utf-8', errors='ignore')
    ai_md = f"""---
file_id: {file_id}
source_mime: {mime}
extraction_version: v1.0
---

{text}
"""
    ai_md_key = f"files/{file_id}/ai/ai.md"
    storage.put_object(ai_md_key, ai_md.encode('utf-8'), 'text/markdown')

    # Stage 3: Mark ready
    job.status = 'ready'
    job.finished_at = datetime.now(timezone.utc)
```

**Integration point** (in main worker loop):
```python
if should_fast_track(file.mime_original, extension):
    process_simple_file(file.id, content, file.mime_original)
else:
    # Existing pipeline for documents, images, etc.
    process_with_full_pipeline(file.id)
```

---

### Phase 2: Add Path Support to Ingested Files

Add a `path` column before migrating fs scripts so paths are unambiguous from day one.

**Migration**: `/backend/alembic/versions/xxx_add_path_to_ingested_files.py`

```python
def upgrade():
    op.add_column('ingested_files',
        sa.Column('path', sa.Text, nullable=True)
    )
    op.create_index('idx_ingested_files_path', 'ingested_files', ['path'])

    # Backfill: set path = filename_original
    op.execute("UPDATE ingested_files SET path = filename_original")

def downgrade():
    op.drop_index('idx_ingested_files_path', table_name='ingested_files')
    op.drop_column('ingested_files', 'path')
```

**Update Model**: `/backend/api/models/file_ingestion.py`

```python
class IngestedFile(Base):
    # ... existing columns ...
    filename_original = Column(Text, nullable=False)
    path = Column(Text, nullable=True, index=True)  # NEW: hierarchical path
    mime_original = Column(Text, nullable=False)
    # ... rest of columns ...
```

**Update API**: Allow specifying folder on upload

```python
@router.post("/", response_model=IngestionResponse)
async def upload_file(
    file: UploadFile,
    folder: str = Form(default=""),  # NEW
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    # Combine folder and filename
    full_path = f"{folder}/{file.filename}".lstrip("/")

    # Create file record with path
    file_record = IngestedFile(
        user_id=user_id,
        filename_original=file.filename,
        path=full_path,  # NEW
        mime_original=file.content_type or "application/octet-stream",
        size_bytes=0  # Set after upload
    )
```

---

### Phase 3: Update fs Skill Scripts

Migrate each `fs` script to use ingestion API instead of `file_objects`.

#### 2.1: Update `list.py`

**File**: `/backend/skills/fs/scripts/list.py`

**Current**: Queries `file_objects` via `FilesService.list_by_prefix()`

**New**: Query `ingested_files` table using `path`

```python
from api.models.file_ingestion import IngestedFile
from api.db.session import get_db

def list_files(user_id: str, directory: str = ".", pattern: str = "*", recursive: bool = False):
    """List ingested files matching criteria."""
    with get_db() as db:
        query = db.query(IngestedFile).filter(
            IngestedFile.user_id == user_id,
            IngestedFile.deleted_at.is_(None)
        )

        # Filter by directory using IngestedFile.path

        files = query.order_by(IngestedFile.created_at.desc()).all()

        entries = []
        for file in files:
            # Apply pattern matching on filename
            if not fnmatch.fnmatch(file.filename_original, pattern):
                continue

            entries.append({
                "name": file.filename_original,
                "path": file.path or file.filename_original,
                "size": file.size_bytes,
                "modified": file.created_at.isoformat(),
                "is_file": True,
                "is_directory": False,
            })

        return {
            "directory": directory,
            "files": entries,
            "count": len(entries)
        }
```

**Challenges**:
- `ingested_files` doesn't have hierarchical paths (just `filename_original`)
- Need to decide: add `path` column or use metadata

**Recommendation**: Add `path` column to `ingested_files` table for folder organization.

---

#### 2.2: Update `read.py`

**File**: `/backend/skills/fs/scripts/read.py`

**Current**: Reads from `file_objects` via `FilesService.get_by_path()`

**New**: Fetch `ai.md` derivative from ingestion storage (include frontmatter + content)

```python
from api.services.file_ingestion_service import FileIngestionService
from api.services.storage.service import get_storage_backend
from uuid import UUID

def read_file(user_id: str, path: str):
    """Read file content from ingested files."""
    with get_db() as db:
        # Option 1: Search by filename
        file = db.query(IngestedFile).filter(
            IngestedFile.user_id == user_id,
            IngestedFile.filename_original == path,
            IngestedFile.deleted_at.is_(None)
        ).first()

        if not file:
            raise FileNotFoundError(f"File not found: {path}")

        # Get ai.md derivative
        derivative = FileIngestionService.get_derivative(db, file.id, "ai_md")

        if not derivative:
            # Fallback: get original if no ai.md
            derivative = FileIngestionService.get_derivative(db, file.id, "text_original")

        if not derivative:
            raise ValueError(f"No readable content for: {path}")

        # Fetch content from storage
        storage = get_storage_backend()
        content_bytes = storage.get_object(derivative.storage_key)
        content = content_bytes.decode('utf-8', errors='ignore')

        return {
            "path": path,
            "content": content,
            "size": derivative.size_bytes,
            "encoding": "utf-8"
        }
```

**Benefits**: AI gets structured `ai.md` content instead of raw files.

---

#### 2.3: Update `write.py`

**File**: `/backend/skills/fs/scripts/write.py`

**Current**: Writes directly to R2 via `FilesService.upsert_file()`

**New**: Create ingestion job via a service helper (avoid calling router directly)

```python
from api.routers.ingestion import create_ingestion_job
from io import BytesIO

def write_file(user_id: str, path: str, content: str, mode: str = "replace"):
    """Write file by creating ingestion job."""

    # Check for existing file
    with get_db() as db:
        existing = db.query(IngestedFile).filter(
            IngestedFile.user_id == user_id,
            IngestedFile.filename_original == path,
            IngestedFile.deleted_at.is_(None)
        ).first()

        if mode == "create" and existing:
            raise FileExistsError(f"File already exists: {path}")

        if mode == "append" and existing:
            # Read existing content and append
            derivative = FileIngestionService.get_derivative(db, existing.id, "text_original")
            if derivative:
                storage = get_storage_backend()
                old_content = storage.get_object(derivative.storage_key).decode('utf-8')
                content = old_content + content
            # Delete old version
            FileIngestionService.delete_file(db, user_id, existing.id)

    # Create in-memory file
    file_bytes = content.encode('utf-8')
    file_obj = BytesIO(file_bytes)
    file_obj.name = path

    # Determine MIME type
    mime = mimetypes.guess_type(path)[0] or "text/plain"

    # Create ingestion job
    result = create_ingestion_job(
        file=file_obj,
        filename=path,
        user_id=user_id,
        mime_type=mime
    )

    return {
        "path": path,
        "action": "created" if not existing else "updated",
        "file_id": result["file_id"],
        "size": len(file_bytes)
    }
```

**Benefits**: All files go through ingestion pipeline automatically.

---

#### 2.4: Update `delete.py`

**File**: `/backend/skills/fs/scripts/delete.py`

**Current**: Marks `file_objects` as deleted

**New**: Use ingestion API (soft delete via ingested_files)

```python
from api.services.file_ingestion_service import FileIngestionService

def delete_file(user_id: str, path: str):
    """Delete ingested file."""
    with get_db() as db:
        file = db.query(IngestedFile).filter(
            IngestedFile.user_id == user_id,
            IngestedFile.path == path,
            IngestedFile.deleted_at.is_(None)
        ).first()

        if not file:
            raise FileNotFoundError(f"File not found: {path}")

        # Soft delete
        file.deleted_at = datetime.now(timezone.utc)
        db.commit()

        return {
            "path": path,
            "deleted": True
        }
```

---

#### 2.5: Update `move.py` and `rename.py`

**Current**: Updates `file_objects.path`

**New**: Update `ingested_files.path` (and `filename_original` if needed)

```python
def move_file(user_id: str, source: str, destination: str):
    """Move/rename ingested file."""
    with get_db() as db:
        file = db.query(IngestedFile).filter(
            IngestedFile.user_id == user_id,
            IngestedFile.path == source,
            IngestedFile.deleted_at.is_(None)
        ).first()

        if not file:
            raise FileNotFoundError(f"Source not found: {source}")

        # Check destination doesn't exist
        existing = db.query(IngestedFile).filter(
            IngestedFile.user_id == user_id,
            IngestedFile.path == destination,
            IngestedFile.deleted_at.is_(None)
        ).first()

        if existing:
            raise FileExistsError(f"Destination exists: {destination}")

        # Update filename
        file.path = destination
        file.filename_original = destination.split("/")[-1]
        db.commit()

        return {
            "source": source,
            "destination": destination
        }
```

---

#### 2.6: Update `info.py`

**Current**: Queries `file_objects`

**New**: Query `ingested_files` and derivatives (via path)

```python
def get_file_info(user_id: str, path: str):
    """Get file metadata."""
    with get_db() as db:
        file = db.query(IngestedFile).filter(
            IngestedFile.user_id == user_id,
            IngestedFile.path == path,
            IngestedFile.deleted_at.is_(None)
        ).first()

        if not file:
            raise FileNotFoundError(f"File not found: {path}")

        job = db.query(FileProcessingJob).filter(
            FileProcessingJob.file_id == file.id
        ).first()

        return {
            "path": path,
            "size": file.size_bytes,
            "mime": file.mime_original,
            "created": file.created_at.isoformat(),
            "status": job.status if job else "unknown",
            "is_file": True,
            "is_directory": False
        }
```

---

### Phase 4: Migrate Existing file_objects Data

Migrate any existing workspace files to ingestion system.

**Migration Script**: `/backend/scripts/migrate_file_objects_to_ingestion.py`

```python
from api.models.file_object import FileObject
from api.models.file_ingestion import IngestedFile
from api.services.storage.service import get_storage_backend
from api.routers.ingestion import create_ingestion_job

def migrate_file_objects():
    """Migrate all file_objects to ingested_files."""
    with get_db() as db:
        file_objects = db.query(FileObject).filter(
            FileObject.deleted_at.is_(None)
        ).all()

        for obj in file_objects:
            print(f"Migrating: {obj.path}")

            # Download from old storage
            storage = get_storage_backend()
            content = storage.get_object(obj.bucket_key)

            # Create ingestion job
            file_obj = BytesIO(content)
            file_obj.name = obj.path.split('/')[-1]  # Extract filename

            result = create_ingestion_job(
                file=file_obj,
                filename=file_obj.name,
                user_id=obj.user_id,
                mime_type=obj.content_type or "application/octet-stream"
            )

            print(f"  → Created file_id: {result['file_id']}")

            # Mark old record as migrated (don't delete yet)
            obj.metadata = obj.metadata or {}
            obj.metadata['migrated_to_file_id'] = result['file_id']
            obj.metadata['migration_date'] = datetime.now(timezone.utc).isoformat()
            db.commit()

if __name__ == "__main__":
    migrate_file_objects()
    print("Migration complete!")
```

**Run migration:**
```bash
cd backend
python scripts/migrate_file_objects_to_ingestion.py
```

---

### Phase 5: Update fs Skill Documentation

**File**: `/backend/skills/fs/SKILL.md`

```markdown
---
name: fs
description: Comprehensive filesystem operations for ingested file storage - list, read, write, delete, move files. Works with both AI-created and user-uploaded files.
metadata:
  capabilities:
    reads: true
    writes: true
    network: false
    external_apis: false
---

# Filesystem Operations (fs)

Complete filesystem CRUD operations for sideBar ingested file storage.

## Base Directory

All operations work with ingested files stored in the unified file system.

## Storage Architecture

Files are stored using the ingestion pipeline:
- Text files (markdown, JSON, etc.) are fast-tracked for instant access
- Binary files (PDFs, images) go through full processing pipeline
- All files get automatic `ai.md` generation for AI context
- Thumbnails generated for supported formats

## Scripts

- `list.py` - List files with filtering
- `read.py` - Read file content (ai.md including frontmatter)
- `write.py` - Create/update files (creates ingestion job)
- `info.py` - Get file metadata and processing status
- `delete.py` - Soft delete files
- `move.py` - Move files
- `rename.py` - Rename files

All scripts support `--json` flag for structured output.

## Security

- User-scoped access (files isolated by user_id)
- Soft deletes with audit trail
- Processing status tracking
```

---

### Phase 6: Deprecate file_objects System

After migration is complete and stable:

1. **Remove file_objects references**:
   - Delete `/backend/api/models/file_object.py`
   - Delete `/backend/api/services/files_service.py`
   - Remove from imports

2. **Drop table** (after backup):
   ```sql
   -- Backup first!
   CREATE TABLE file_objects_backup AS SELECT * FROM file_objects;

   -- Then drop
   DROP TABLE file_objects;
   ```

3. **Clean up old storage** (optional):
   - Old R2 keys like `users/{user_id}/*` can be archived or deleted

---

## Testing Strategy

### Unit Tests

**Test each fs script**:
```bash
# Test write → read → delete flow
python scripts/write.py test.txt --content "Hello World" --user-id {uuid} --json
python scripts/read.py test.txt --user-id {uuid} --json
python scripts/delete.py test.txt --user-id {uuid} --json

# Test list with patterns
python scripts/list.py . --pattern "*.txt" --user-id {uuid} --json

# Test move/rename
python scripts/write.py old.txt --content "Test" --user-id {uuid} --json
python scripts/move.py old.txt new.txt --user-id {uuid} --json
```

### Integration Tests

**Test AI workflow**:
1. AI writes file via fs skill
2. Check it appears in UI Files panel
3. User opens file in viewer
4. AI can read it back
5. AI can list all files

**Test user workflow**:
1. User uploads file via UI
2. AI lists files and sees it
3. AI reads file content
4. AI can reference file in responses

### Manual Testing

**Verify unification**:
- [ ] Upload PDF via UI → Appears in `fs list`
- [ ] AI writes markdown via `fs write` → Appears in UI Files panel
- [ ] Both files show processing status
- [ ] Both files have ai.md derivatives
- [ ] Both files appear in recent activity prompt context

---

## Migration Checklist

### Preparation
- [ ] Review FILE_INGESTION_PLAN.md
- [ ] Backup `file_objects` table
- [ ] Backup R2 storage bucket

### Phase 1: Fast-Track Processing
- [ ] Add `should_fast_track()` function to worker
- [ ] Implement `process_simple_file()` for text files
- [ ] Test with sample .txt, .md, .json files
- [ ] Verify ai.md generation works

### Phase 2: Add Path Support
- [ ] Update `list.py` to query ingested_files
- [ ] Update `read.py` to fetch ai.md derivatives
- [ ] Update `write.py` to create ingestion jobs
- [ ] Update `delete.py` to soft delete ingested files
- [ ] Update `move.py` and `rename.py`
- [ ] Update `info.py` to show processing status
- [ ] Test each script independently

### Phase 3: Update fs Scripts
- [ ] Create migration for `path` column
- [ ] Update IngestedFile model
- [ ] Update upload API to accept folder parameter
- [ ] Update fs scripts to use path instead of filename
- [ ] Test hierarchical organization

### Phase 4: Data Migration
- [ ] Write migration script
- [ ] Test on development database
- [ ] Run migration on production
- [ ] Verify all files migrated successfully
- [ ] Test file access after migration

### Phase 5: Documentation
- [ ] Update fs SKILL.md
- [ ] Update API documentation
- [ ] Add migration notes to changelog
- [ ] Update developer guide

### Phase 6: Cleanup
- [ ] Monitor for 1 week post-migration
- [ ] Remove file_objects code
- [ ] Drop file_objects table
- [ ] Archive old R2 storage (optional)

---

## Rollback Plan

If issues occur:

1. **Re-enable file_objects**:
   ```bash
   git checkout HEAD~1 -- backend/skills/fs/
   ```

2. **Restore table** (if dropped):
   ```sql
   CREATE TABLE file_objects AS SELECT * FROM file_objects_backup;
   ```

3. **Revert migrations**:
   ```bash
   cd backend
   alembic downgrade -1
   ```

---

## Success Criteria

✅ AI can write files that users see in UI
✅ User uploads are visible to AI via fs skill
✅ All files go through ingestion pipeline
✅ Fast-track processing for text files (< 1 second)
✅ Hierarchical folder organization works
✅ File search and filtering works
✅ Processing status visible in fs info
✅ No duplicate storage systems
✅ file_objects table deprecated

---

## Future Enhancements

After migration is stable:

1. **Advanced search**: Full-text search across ai.md content
2. **Batch operations**: Upload/delete multiple files
3. **Sharing**: Share files between users
4. **Versioning**: Track file history and changes
5. **Tags**: Add metadata tags to files
6. **Collections**: Group related files together
