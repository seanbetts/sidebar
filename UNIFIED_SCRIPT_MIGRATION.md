# Plan: Unified Script-Based Architecture for UI and AI Agent

## Executive Summary

**Project**: Agent Smith - AI assistant development environment with extensible skills system

**Goal**: Unify code execution paths so UI and AI agent use the same underlying scripts for operations

**Current Problem**: UI and AI use completely different code to perform the same actions:
- UI calls backend REST endpoints → direct SQLAlchemy database queries
- AI agent calls skill scripts → writes to filesystem as markdown files
- Result: Duplicate logic, divergent behavior, no real-time UI updates when AI acts

**Solution**: Create service layer as single source of truth, refactor scripts to use database, emit SSE events for UI reactivity

**Impact**: Enables real-time collaborative experience where AI actions immediately visible in UI

---

## Background: Application Architecture

### Technology Stack
- **Frontend**: SvelteKit + TypeScript + Tailwind CSS
- **Backend**: FastAPI + SQLAlchemy ORM + PostgreSQL
- **AI**: Claude API via Anthropic SDK
- **Protocols**: REST API + MCP (Model Context Protocol)
- **Deployment**: Docker Compose (3 services: postgres, skills-api, frontend)

### Key Concepts

**MCP (Model Context Protocol)**: Standard protocol for AI tools/functions. Allows Claude to call predefined tools with structured parameters.

**Skills**: Modular packages that extend AI agent capabilities. Each skill has:
- `SKILL.md` - Documentation with YAML frontmatter (name, description, capabilities)
- `scripts/` - Executable Python scripts that perform actual operations
- Example: `notes` skill has `save_markdown.py` script

**SkillExecutor**: Security layer that runs skill scripts as subprocess with:
- Path validation (prevents directory traversal)
- Timeout controls (30s default)
- Output size limits (10MB max)
- Audit logging (tracks all executions)
- Skill whitelist (only approved skills can run)

**SSE (Server-Sent Events)**: HTTP streaming protocol. Backend pushes events to frontend in real-time. Used for chat streaming and tool execution status.

**Svelte Stores**: Reactive state management in frontend. When store updates, UI automatically re-renders.

### Current Data Flow

**UI creates a note:**
```
User clicks "New Note"
  → Frontend calls POST /api/files/content
    → Files router extracts title from markdown H1
      → Direct SQLAlchemy: db.add(Note(...))
        → db.commit()
          → Frontend manually calls filesStore.load('notes')
            → UI re-renders with new note
```

**AI creates a note:**
```
User asks "Create a note about X"
  → Claude API returns tool_use block
    → tool_mapper.execute_tool("fs_write", {path: "notes/file.md", content: "..."})
      → SkillExecutor runs subprocess: python save_markdown.py "Title" --content "..." --json
        → Script writes to /workspace/notes/YYYY/Month/title.md
          → Returns JSON: {"success": true, "path": "..."}
            → UI has no idea this happened (filesystem not monitored)
```

**Problem**: Two completely different code paths, no shared logic, UI blind to AI actions.

---

## Current State Analysis

### The Problem
The UI and AI Agent currently use **completely different code paths** for the same operations:

**UI Flow:**
```
Frontend → Backend API Endpoints → Direct SQLAlchemy Queries → Database
```

**AI Agent Flow:**
```
Claude → tool_mapper → SkillExecutor (subprocess) → Skill Scripts → Filesystem (files)
```

### Critical Findings

1. **Backend endpoints** (notes, websites) use direct SQLAlchemy queries to database
2. **Skill scripts** (notes, web-save) write to filesystem as markdown files
3. **No overlap** - UI doesn't use scripts, scripts don't use database
4. **SSE infrastructure** already exists for real-time updates during chat
5. **Frontend stores** use manual refetch pattern after mutations

### Key Insight
The skill scripts are NOT broken by the database migration - they simply never used the database. They're still writing to files while the UI writes to the database. This is the core divergence we need to fix.

---

## Architecture Design

### 1. Dual-Pattern Architecture

**Recognition**: Two distinct operation types require different approaches:

**Pattern A: Database Operations** (Structured Data)
- Applies to: Notes, Websites, Conversations
- Storage: PostgreSQL with SQLAlchemy ORM
- Architecture: Service Layer + Subprocess (dual-mode scripts)

**Pattern B: Filesystem Operations** (File Storage)
- Applies to: Documents, PDFs, Word files, PowerPoint (future file ingestion)
- Storage: `/workspace/documents/` filesystem
- Architecture: Existing filesystem scripts (no changes needed)

### 2. Service Layer Pattern (Database Operations)

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                     Service Layer                            │
│  notes_service.py, websites_service.py                      │
│  - Single source of truth for business logic                │
│  - Takes database session as parameter                      │
│  - Returns ORM models or raises exceptions                  │
└─────────────────────────────────────────────────────────────┘
          ↑                                    ↑
          │                                    │
    ┌─────┴─────┐                      ┌──────┴──────┐
    │  Scripts  │                      │  Endpoints  │
    │  (AI)     │                      │  (UI)       │
    └───────────┘                      └─────────────┘
```

**Script Execution (AI Agent):**
```python
# skill: notes/scripts/save_markdown.py
# AI agent calls via subprocess with --database flag

from api.db.session import SessionLocal
from api.services.notes_service import NotesService

def main():
    parser.add_argument('--database', action='store_true')
    args = parser.parse_args()

    if args.database:  # Database mode (NEW)
        db = SessionLocal()
        try:
            note = NotesService.create_note(
                db=db,
                title=args.title,
                content=args.content,
                folder=args.folder
            )
            print(json.dumps({
                "success": True,
                "data": {"id": str(note.id), "title": note.title}
            }))
        finally:
            db.close()
    else:  # Filesystem mode (LEGACY - deprecated)
        # ... existing file-based logic
```

**Endpoint Integration (UI):**
```python
# backend/api/routers/files.py (modify existing)

from api.services.notes_service import NotesService

@router.post("/api/files/content")
async def create_note(request: dict, db: Session = Depends(get_db)):
    if request["basePath"] == "notes":
        # Use service layer directly
        note = NotesService.create_note(
            db=db,
            content=request["content"],
            folder=request.get("folder", "")
        )
        return {"success": True, "id": str(note.id)}
```

**Benefits:**
- Maintains subprocess security isolation for AI agent
- Shares business logic via service layer
- Gradual migration with `--database` flag
- Existing audit logging still works

### 3. Tool Mapper Integration (AI Agent)

**Update tool definitions to use database mode:**

```python
# backend/api/services/tool_mapper.py (modify)

def get_claude_tools(self) -> list[dict]:
    return [
        # ... existing filesystem tools ...

        # NEW: Database-backed tools
        {
            "name": "notes_create",
            "description": "Create a new markdown note in the database (visible in UI)",
            "input_schema": {
                "type": "object",
                "properties": {
                    "title": {"type": "string", "description": "Note title"},
                    "content": {"type": "string", "description": "Markdown content"},
                    "folder": {"type": "string", "description": "Optional folder path"}
                },
                "required": ["title", "content"]
            }
        },
        {
            "name": "website_save",
            "description": "Save a website as markdown to the database (visible in UI)",
            "input_schema": {
                "type": "object",
                "properties": {
                    "url": {"type": "string", "description": "URL to save"}
                },
                "required": ["url"]
            }
        }
    ]

def execute_tool(self, name: str, tool_input: dict) -> dict:
    # ... existing tools ...

    if name == "notes_create":
        args = [
            tool_input["title"],
            "--content", tool_input["content"],
            "--database",  # KEY: Enable database mode
            "--json"
        ]
        if tool_input.get("folder"):
            args.extend(["--folder", tool_input["folder"]])

        result = self.executor.execute("notes", "save_markdown.py", args)
        return json.loads(result["output"])

    elif name == "website_save":
        args = [
            tool_input["url"],
            "--database",  # KEY: Enable database mode
            "--json"
        ]
        result = self.executor.execute("web-save", "save_url.py", args)
        return json.loads(result["output"])
```

### 4. Frontend Reactivity via Specific SSE Events

**Event Types to Implement:**
- `note_created` - Emitted when AI creates a note
- `note_updated` - Emitted when AI updates a note
- `note_deleted` - Emitted when AI deletes a note
- `website_saved` - Emitted when AI saves a website
- `website_deleted` - Emitted when AI deletes a website

**Backend - Emit events in claude_client.py:**

```python
# backend/api/services/claude_client.py (modify stream_with_tools method)

async for event in self._process_stream(messages, tools):
    if event["type"] == "tool_result":
        # Emit standard tool result
        yield event

        # NEW: Emit specific UI update events
        tool_name = event.get("tool_name")  # Need to track this
        result = event.get("result", {})

        if tool_name == "notes_create" and result.get("success"):
            yield {
                "type": "note_created",
                "data": {
                    "id": result["data"]["id"],
                    "title": result["data"]["title"],
                    "folder": result["data"].get("folder")
                }
            }
        elif tool_name == "notes_update" and result.get("success"):
            yield {
                "type": "note_updated",
                "data": {
                    "id": result["data"]["id"],
                    "title": result["data"]["title"]
                }
            }
        elif tool_name == "website_save" and result.get("success"):
            yield {
                "type": "website_saved",
                "data": {
                    "id": result["data"]["id"],
                    "url": result["data"]["url"],
                    "title": result["data"]["title"]
                }
            }
    else:
        yield event
```

**Frontend - SSE Client Handler:**

```typescript
// frontend/src/lib/api/sse.ts (modify)

export interface SSECallbacks {
    onToken?: (content: string) => void;
    onToolCall?: (event: any) => void;
    onToolResult?: (event: any) => void;
    onComplete?: () => void;
    onError?: (error: string) => void;
    // NEW: Specific event handlers
    onNoteCreated?: (data: { id: string; title: string; folder?: string }) => void;
    onNoteUpdated?: (data: { id: string; title: string }) => void;
    onNoteDeleted?: (data: { id: string }) => void;
    onWebsiteSaved?: (data: { id: string; url: string; title: string }) => void;
    onWebsiteDeleted?: (data: { id: string }) => void;
}

private handleEvent(event: string, data: any) {
    switch (event) {
        case 'token':
            this.callbacks.onToken?.(data.content);
            break;
        case 'tool_call':
            this.callbacks.onToolCall?.(data);
            break;
        case 'tool_result':
            this.callbacks.onToolResult?.(data);
            break;
        case 'complete':
            this.callbacks.onComplete?.();
            break;
        case 'error':
            this.callbacks.onError?.(data.error);
            break;
        // NEW: Specific UI update events
        case 'note_created':
            this.callbacks.onNoteCreated?.(data);
            break;
        case 'note_updated':
            this.callbacks.onNoteUpdated?.(data);
            break;
        case 'note_deleted':
            this.callbacks.onNoteDeleted?.(data);
            break;
        case 'website_saved':
            this.callbacks.onWebsiteSaved?.(data);
            break;
        case 'website_deleted':
            this.callbacks.onWebsiteDeleted?.(data);
            break;
    }
}
```

**Frontend - ChatWindow Integration:**

```typescript
// frontend/src/lib/components/ChatWindow.svelte (modify)

import { filesStore } from '$lib/stores/files';
import { websitesStore } from '$lib/stores/websites';
import { editorStore } from '$lib/stores/editor';

async function handleSend(message: string) {
    const assistantMessageId = await chatStore.sendMessage(message);

    await sseClient.connect(message, {
        onToken: (content) => {
            chatStore.appendToken(assistantMessageId, content);
        },
        onToolCall: (event) => {
            chatStore.addToolCall(assistantMessageId, event);
        },
        onToolResult: (event) => {
            chatStore.updateToolResult(assistantMessageId, event);
        },
        // NEW: Real-time UI updates when AI acts
        onNoteCreated: async (data) => {
            await filesStore.load('notes');
            // Optionally open the new note in editor
            if (shouldOpenNote) {
                await editorStore.loadNote('notes', data.id);
            }
        },
        onNoteUpdated: async (data) => {
            await filesStore.load('notes');
            // If this note is open in editor, reload it
            if (editorStore.currentNoteId === data.id) {
                await editorStore.loadNote('notes', data.id);
            }
        },
        onWebsiteSaved: async (data) => {
            await websitesStore.load();
        },
        onComplete: async () => {
            await chatStore.finishStreaming(assistantMessageId);
        },
        onError: (error) => {
            chatStore.setError(assistantMessageId, error);
        }
    });
}
```

---

## Implementation Plan

### Phase 1: Service Layer Foundation (CRITICAL)

**Goal:** Create reusable service layer for database operations

**Why**: Service layer is the single source of truth. Both UI endpoints and AI scripts will call these services, ensuring identical behavior.

#### Step 1.1: Create Notes Service

**File**: `backend/api/services/notes_service.py`

**Implementation**:

```python
"""Notes service - unified business logic for notes operations."""
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from backend.api.models.note import Note
from datetime import datetime, timezone
from typing import List, Optional
import uuid
import re

class NotFoundError(Exception):
    """Raised when a note is not found."""
    pass

class NotesService:
    """Service layer for notes operations."""

    # Regex to extract H1 heading from markdown
    H1_PATTERN = re.compile(r"^#\s+(.+)$", re.MULTILINE)

    @staticmethod
    def extract_title(content: str, fallback: str = "Untitled Note") -> str:
        """
        Extract title from markdown H1 heading.

        Args:
            content: Markdown content
            fallback: Default title if no H1 found

        Returns:
            Extracted title or fallback
        """
        match = NotesService.H1_PATTERN.search(content or "")
        return match.group(1).strip() if match else fallback

    @staticmethod
    def create_note(
        db: Session,
        content: str,
        folder: str = "",
        title: Optional[str] = None,
        tags: Optional[List[str]] = None
    ) -> Note:
        """
        Create a new note in the database.

        Args:
            db: SQLAlchemy session
            content: Markdown content
            folder: Optional folder path for organization
            title: Optional explicit title (extracted from content if None)
            tags: Optional list of tags

        Returns:
            Created Note model

        Raises:
            IntegrityError: If database constraint violated
        """
        now = datetime.now(timezone.utc)

        # Auto-extract title from markdown H1 if not provided
        if not title:
            title = NotesService.extract_title(content)

        # Build metadata JSONB
        metadata = {
            "folder": folder,
            "pinned": False
        }
        if tags:
            metadata["tags"] = tags

        # Create note
        note = Note(
            title=title,
            content=content,
            metadata_=metadata,
            created_at=now,
            updated_at=now,
            last_opened_at=None,
            deleted_at=None
        )

        try:
            db.add(note)
            db.commit()
            db.refresh(note)
            return note
        except IntegrityError as e:
            db.rollback()
            raise ValueError(f"Database constraint violated: {e}")
        except Exception as e:
            db.rollback()
            raise

    @staticmethod
    def update_note(
        db: Session,
        note_id: uuid.UUID,
        content: str,
        title: Optional[str] = None
    ) -> Note:
        """
        Update existing note content.

        Args:
            db: SQLAlchemy session
            note_id: UUID of note to update
            content: New markdown content
            title: Optional new title (extracted from content if None)

        Returns:
            Updated Note model

        Raises:
            NotFoundError: If note doesn't exist or is deleted
        """
        note = db.query(Note).filter(
            Note.id == note_id,
            Note.deleted_at.is_(None)
        ).first()

        if not note:
            raise NotFoundError(f"Note not found: {note_id}")

        # Update title from content if not explicitly provided
        if not title:
            title = NotesService.extract_title(content, note.title)

        note.title = title
        note.content = content
        note.updated_at = datetime.now(timezone.utc)

        try:
            db.commit()
            db.refresh(note)
            return note
        except Exception as e:
            db.rollback()
            raise

    @staticmethod
    def delete_note(db: Session, note_id: uuid.UUID) -> bool:
        """
        Soft delete a note (set deleted_at timestamp).

        Args:
            db: SQLAlchemy session
            note_id: UUID of note to delete

        Returns:
            True if deleted, False if not found
        """
        note = db.query(Note).filter(
            Note.id == note_id,
            Note.deleted_at.is_(None)
        ).first()

        if not note:
            return False

        note.deleted_at = datetime.now(timezone.utc)
        note.updated_at = datetime.now(timezone.utc)

        try:
            db.commit()
            return True
        except Exception as e:
            db.rollback()
            raise

    @staticmethod
    def get_note(db: Session, note_id: uuid.UUID, mark_opened: bool = True) -> Optional[Note]:
        """
        Get a single note by ID.

        Args:
            db: SQLAlchemy session
            note_id: UUID of note
            mark_opened: If True, update last_opened_at timestamp

        Returns:
            Note model or None if not found
        """
        note = db.query(Note).filter(
            Note.id == note_id,
            Note.deleted_at.is_(None)
        ).first()

        if note and mark_opened:
            note.last_opened_at = datetime.now(timezone.utc)
            db.commit()
            db.refresh(note)

        return note

    @staticmethod
    def list_notes(
        db: Session,
        folder: Optional[str] = None,
        search: Optional[str] = None
    ) -> List[Note]:
        """
        List notes with optional filtering.

        Args:
            db: SQLAlchemy session
            folder: Optional folder path filter
            search: Optional search term (searches title and content)

        Returns:
            List of Note models
        """
        query = db.query(Note).filter(Note.deleted_at.is_(None))

        if folder:
            # Filter by folder in JSONB metadata
            query = query.filter(Note.metadata_["folder"].astext == folder)

        if search:
            # Search in title and content
            search_term = f"%{search}%"
            query = query.filter(
                (Note.title.ilike(search_term)) |
                (Note.content.ilike(search_term))
            )

        return query.order_by(Note.updated_at.desc()).all()
```

**Testing**:
- [ ] Create unit test file: `backend/tests/test_notes_service.py`
- [ ] Test create_note with various inputs
- [ ] Test title extraction from H1
- [ ] Test update_note preserves metadata
- [ ] Test delete_note soft deletes
- [ ] Test list_notes filtering and search
- [ ] Test error cases (not found, invalid data)

#### Step 1.2: Create Websites Service
- [ ] Create `backend/api/services/websites_service.py`
- [ ] Implement `WebsitesService` class with static methods:
  - [ ] `save_website(db, url, title, content, metadata)` → Website
  - [ ] `delete_website(db, website_id)` → bool
  - [ ] `get_website(db, website_id)` → Website
  - [ ] `list_websites(db)` → List[Website]
- [ ] Handle URL normalization and metadata extraction
- [ ] Transaction handling

#### Step 1.3: Write Tests for Services
- [ ] Unit tests for NotesService (mock database)
- [ ] Unit tests for WebsitesService
- [ ] Test edge cases (duplicates, missing data, etc.)

---

### Phase 2: Refactor Notes Skill for Database (HIGH PRIORITY)

**Goal:** Make notes skill database-aware while maintaining CLI compatibility

#### Step 2.1: Refactor save_markdown.py Script

**File**: `backend/skills/notes/scripts/save_markdown.py`

**Changes Required**:
1. Add `--database` flag to enable database mode
2. Import `SessionLocal` and `NotesService`
3. Create dual-mode function routing
4. Maintain backward compatibility with filesystem mode

**Key Code Sections**:

```python
# Add these imports at the top
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))
from api.db.session import SessionLocal
from api.services.notes_service import NotesService

# New database mode function
def save_markdown_to_database(title, content, folder="", tags=None):
    db = SessionLocal()
    try:
        note = NotesService.create_note(
            db=db, content=content, folder=folder, title=title, tags=tags
        )
        return {
            "success": True,
            "data": {"id": str(note.id), "title": note.title, ...}
        }
    finally:
        db.close()

# Add --database flag to argparse
parser.add_argument("--database", action="store_true",
                   help="Save to database instead of filesystem")

# Route based on flag
if args.database:
    result = save_markdown_to_database(...)
else:
    result = save_markdown_to_filesystem(...)  # existing logic
```

**Testing Steps**:
- [ ] Test database mode creates note in Postgres
- [ ] Test filesystem mode still works (fallback)
- [ ] Verify JSON output format matches expected structure
- [ ] Test error handling (network issues, DB connection failures)

#### Step 2.2: Update tool_mapper for Notes

**File**: `backend/api/services/tool_mapper.py`

**Changes Required**:
1. Add new MCP tool definitions for database-backed note operations
2. Update `execute_tool()` to pass `--database` flag
3. Parse JSON output from scripts

**Code Changes**:

```python
# In get_claude_tools() method, add these tool definitions:

{
    "name": "notes_create",
    "description": "Create a new markdown note in the database (visible in UI). Use this instead of fs_write for notes that should appear in the notes panel.",
    "input_schema": {
        "type": "object",
        "properties": {
            "title": {
                "type": "string",
                "description": "Note title (optional - will be extracted from H1 if empty)"
            },
            "content": {
                "type": "string",
                "description": "Markdown content with H1 heading"
            },
            "folder": {
                "type": "string",
                "description": "Optional folder path for organization (e.g., 'Projects/Website Redesign')"
            },
            "tags": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Optional list of tags"
            }
        },
        "required": ["content"]
    }
},
{
    "name": "notes_update",
    "description": "Update an existing note by ID",
    "input_schema": {
        "type": "object",
        "properties": {
            "note_id": {"type": "string", "description": "UUID of note to update"},
            "content": {"type": "string", "description": "New markdown content"}
        },
        "required": ["note_id", "content"]
    }
}

# In execute_tool() method, add these cases:

elif name == "notes_create":
    # Build arguments for script
    args = [
        tool_input.get("title", ""),  # Empty string if not provided
        "--content", tool_input["content"],
        "--database",  # KEY: Enable database mode
        "--json"
    ]
    if tool_input.get("folder"):
        args.extend(["--folder", tool_input["folder"]])
    if tool_input.get("tags"):
        args.extend(["--tags", ",".join(tool_input["tags"])])

    # Execute script via SkillExecutor
    result = self.executor.execute("notes", "save_markdown.py", args)

    # Parse JSON output
    output = json.loads(result["output"])
    if not output.get("success"):
        raise ValueError(f"Note creation failed: {output.get('error')}")

    return output["data"]

elif name == "notes_update":
    # Similar pattern for update
    args = [
        tool_input["note_id"],
        "--content", tool_input["content"],
        "--database",
        "--json",
        "--mode", "update"
    ]
    result = self.executor.execute("notes", "update_note.py", args)
    output = json.loads(result["output"])
    return output["data"] if output.get("success") else {"error": output.get("error")}
```

**Testing Steps**:
- [ ] Test tool definition appears in Claude's available tools
- [ ] Test AI agent can call `notes_create` via chat
- [ ] Verify `--database` flag is passed to script
- [ ] Verify JSON parsing works correctly
- [ ] Test error handling when script fails

#### Step 2.3: Refactor Files Router to Use Service
- [ ] In `POST /api/files/content` (basePath='notes'):
  - [ ] Import NotesService
  - [ ] Replace direct SQLAlchemy with `NotesService.create_note()`
  - [ ] Remove duplicate title extraction logic
  - [ ] Maintain existing response format
- [ ] Test UI note creation still works

---

### Phase 3: Real-Time UI Reactivity (CRITICAL FOR UX)

**Goal:** Enable UI to update when AI performs actions

#### Step 3.1: Add SSE Event Emission in claude_client.py
- [ ] Track tool_name in event context
- [ ] After successful tool_result, emit specific events:
  - [ ] `note_created` with {id, title, folder}
  - [ ] `note_updated` with {id, title}
  - [ ] `website_saved` with {id, url, title}
- [ ] Only emit on success (check result.success)

#### Step 3.2: Update Frontend SSE Client
- [ ] Add new callback types to `SSECallbacks` interface
- [ ] Add cases in `handleEvent()` switch for new events
- [ ] Export typed event data interfaces

#### Step 3.3: Wire Up Store Updates in ChatWindow
- [ ] Add event handlers:
  - [ ] `onNoteCreated` → `filesStore.load('notes')`
  - [ ] `onNoteUpdated` → reload if open in editor
  - [ ] `onWebsiteSaved` → `websitesStore.load()`
- [ ] Test real-time updates work during chat

---

### Phase 4: Refactor Websites Skill for Database

**Goal:** Migrate web-save to database storage

#### Step 4.1: Refactor save_url.py Script
- [ ] Add `--database` flag
- [ ] Import WebsitesService
- [ ] Implement database mode:
  - [ ] Fetch URL via Jina.ai (keep existing logic)
  - [ ] Parse markdown and extract metadata
  - [ ] Call `WebsitesService.save_website(db, ...)`
  - [ ] Return JSON with website ID
- [ ] Keep filesystem mode as fallback

#### Step 4.2: Update tool_mapper for Websites
- [ ] Add tool definition `website_save`
- [ ] Execute with `--database` flag
- [ ] Test AI can save websites

#### Step 4.3: Refactor Websites Router (if needed)
- [ ] Check if POST `/api/websites` endpoint exists
- [ ] If yes, refactor to use WebsitesService
- [ ] If no, create endpoint for UI to save websites

---

### Phase 5: Additional CRUD Operations (INCREMENTAL)

**Goal:** Complete the CRUD suite for notes and websites

#### Step 5.1: Notes Update/Delete Scripts
- [ ] Create/refactor scripts:
  - [ ] `update_note.py` with `--database` flag
  - [ ] `delete_note.py` with `--database` flag
  - [ ] `read_note.py` (if needed)
- [ ] Add tool definitions in tool_mapper
- [ ] Update Files router to use services for update/delete

#### Step 5.2: Websites Delete Script
- [ ] Create `delete_website.py` with `--database` flag
- [ ] Add tool definition
- [ ] Update router

#### Step 5.3: Add More SSE Events
- [ ] Emit `note_deleted`, `website_deleted`
- [ ] Handle in frontend

---

### Phase 6: Cleanup and Optimization (FUTURE)

**Goal:** Remove technical debt and optimize

#### Step 6.1: Remove Filesystem Fallbacks
- [ ] Remove `else` branch in scripts (filesystem mode)
- [ ] Make `--database` flag the default
- [ ] Deprecate old filesystem-based tools

#### Step 6.2: Data Migration (if needed)
- [ ] Script to migrate any existing filesystem notes to database
- [ ] Script to migrate existing filesystem websites to database

#### Step 6.3: Performance Optimization
- [ ] Add database indexes if needed
- [ ] Optimize SSE event emission (debouncing)
- [ ] Consider caching frequently accessed data

---

### Phase 7: Filesystem Skills (NO CHANGES)

**Decision:** Keep these skills as-is (file-based operations)
- `fs` - Workspace file operations
- `local-read`, `local-write`, `local-manage` - Local document operations
- `docx`, `pdf`, `pptx` - Document processing
- `audio-transcribe`, `youtube-*` - Media processing

These are inherently file-based and should remain so for future document ingestion features.

---

## Critical Files to Create/Modify

### New Files (Phase 1-4)
1. **`backend/api/services/notes_service.py`** - Core notes business logic
2. **`backend/api/services/websites_service.py`** - Core websites business logic

### Modified Files (Phase 1-4)

**Backend:**
1. **`backend/skills/notes/scripts/save_markdown.py`**
   - Add `--database` flag
   - Import NotesService
   - Dual-mode operation (DB + filesystem fallback)

2. **`backend/skills/web-save/scripts/save_url.py`**
   - Add `--database` flag
   - Import WebsitesService
   - Dual-mode operation (DB + filesystem fallback)

3. **`backend/api/services/tool_mapper.py`**
   - Add tool definitions: `notes_create`, `notes_update`, `website_save`
   - Update `execute_tool()` to pass `--database` flag
   - Parse JSON output from scripts

4. **`backend/api/services/claude_client.py`**
   - Add SSE event emission after successful tool execution
   - Track tool_name in event context
   - Emit specific events: `note_created`, `note_updated`, `website_saved`

5. **`backend/api/routers/files.py`**
   - Import NotesService
   - Replace direct SQLAlchemy with service calls
   - Maintain existing API contract

**Frontend:**
6. **`frontend/src/lib/api/sse.ts`**
   - Add new callback types to `SSECallbacks` interface
   - Add cases for new events in `handleEvent()`

7. **`frontend/src/lib/components/ChatWindow.svelte`**
   - Add event handlers for store updates
   - Import filesStore, websitesStore, editorStore
   - Wire up `onNoteCreated`, `onWebsiteSaved`, etc.

### Files to Keep Unchanged
- All filesystem skill scripts (`fs/`, `local-*/`, `docx/`, `pdf/`, etc.)
- Database models (`backend/api/models/`) - no schema changes
- Frontend stores (`frontend/src/lib/stores/`) - internal structure unchanged
- SSE streaming infrastructure - only extend, don't modify core

---

## Architecture Decisions Summary

### 1. Service Layer Pattern
- **Decision**: Create service layer as single source of truth
- **Rationale**: Enables code sharing without breaking subprocess security model
- **Trade-off**: Adds layer of abstraction, but reduces duplication

### 2. Dual-Mode Scripts
- **Decision**: Scripts support both `--database` and filesystem modes
- **Rationale**: Gradual migration, can roll back if needed
- **Trade-off**: Temporary complexity during transition

### 3. Subprocess Execution Maintained
- **Decision**: Keep SkillExecutor subprocess pattern for AI agent
- **Rationale**: Preserves security isolation and audit logging
- **Trade-off**: Slight performance overhead vs direct function calls

### 4. Specific SSE Events
- **Decision**: Emit event per action type (`note_created` not `data_changed`)
- **Rationale**: More granular control, better UX (can open new note immediately)
- **Trade-off**: More event types to maintain

### 5. Database-First for Structured Data
- **Decision**: Notes, websites, conversations → database; files → filesystem
- **Rationale**: Structured data benefits from RDBMS (search, relations, transactions)
- **Trade-off**: Two storage patterns to maintain

---

## Success Criteria

### Functional Requirements
- [ ] Creating a note from UI and AI agent uses the same service layer code
- [ ] When AI creates a note during chat, UI notes panel updates in real-time
- [ ] When AI saves a website during chat, UI websites panel updates in real-time
- [ ] All existing UI functionality continues to work without breaking changes
- [ ] AI agent can create/update/delete notes and websites using new tools

### Technical Requirements
- [ ] No duplicate business logic between endpoints and scripts
- [ ] Service layer has >80% test coverage
- [ ] SSE events emit reliably and UI handles them gracefully
- [ ] Database transactions are properly scoped (no deadlocks)
- [ ] Audit logging captures both UI and AI actions

### User Experience Requirements
- [ ] UI updates feel instantaneous when AI performs actions
- [ ] No visible lag or race conditions
- [ ] Error messages are clear and actionable
- [ ] Notes and websites created by AI are immediately accessible in UI

### Performance Requirements
- [ ] No regression in UI responsiveness
- [ ] Database queries remain under 100ms for common operations
- [ ] SSE event emission adds <10ms to tool execution
- [ ] Frontend store updates complete in <200ms

---

## Risk Mitigation

### Risk: Database Migration Breaks Existing Data
- **Mitigation**: Scripts keep filesystem fallback mode during transition
- **Rollback**: Can switch back to filesystem mode with feature flag

### Risk: SSE Event Flood Overwhelms Frontend
- **Mitigation**: Only emit events on successful operations
- **Mitigation**: Frontend debounces store refresh (max once per 500ms)

### Risk: Transaction Deadlocks
- **Mitigation**: Keep transactions short-lived (single operation)
- **Mitigation**: No nested transactions

### Risk: Breaking Changes to API
- **Mitigation**: Maintain exact same request/response format in endpoints
- **Mitigation**: Only change internal implementation, not contracts

---

## Next Steps After Plan Approval

1. Create service layer (Phase 1)
2. Write comprehensive tests for services
3. Refactor notes script with `--database` flag (Phase 2)
4. Update tool_mapper for notes
5. Add SSE event emission (Phase 3)
6. Test end-to-end flow (UI → service, AI → script → service)
7. Repeat for websites (Phase 4)
8. Iterate on additional CRUD operations (Phase 5+)
