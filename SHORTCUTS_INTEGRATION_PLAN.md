# Apple Shortcuts Integration Plan

## Executive Summary

**V1 Scope:** Focused on essential quick capture workflows only. Advanced features moved to future development.

**V1 Features:**
- ✅ **Personal Access Token (PAT) auth** - Managed in user settings (complete)
- ✅ **Scratchpad quick capture** - Append by default; prepend for Shortcuts only (complete)
- ✅ **Notes creation** - Quick note capture with optional title (title stored separately) (complete)
- ✅ **Website saving** - Save URLs with auto-fetched content (fail if fetch fails) (complete)
- ✅ **File ingestion (Shortcuts upload)** - Quick upload via multipart; originals are removed after ingestion (complete)

**Moved to Future:**
- 📋 Note templates (Phase 4)
- 💬 Chat with sideBar (Phase 3)
- 🔗 Webhooks (Phase 5)
- 🎨 Templates/Webhooks management UI (Phase 6)

**V1 Implementation Time:** ~3 hours (Auth + Quick Capture only)

---

## Ambition

Enable seamless integration between sideBar and Apple Shortcuts for rapid capture and automation workflows. Personal use focused - simple, powerful, no over-engineering.

**Core Philosophy:**
- Quick capture from any Apple device (iPhone, iPad, Mac, Apple Watch)
- Voice-first workflows via Siri
- Zero-friction daily usage

**V1 Capabilities:**
1. **Quick Capture:** Add to scratchpad, save websites, create notes via Shortcuts
2. **Personal Access Token:** Simple, secure authentication for all Shortcuts
3. **File Ingestion:** Upload a file from Shortcuts to the ingestion pipeline

---

## Architecture Overview

### Authentication Model

**Unified Bearer Token Authentication** (JWT + PAT support)

The existing `verify_bearer_token` middleware is enhanced to support BOTH:
1. **Supabase JWT tokens** (existing web UI auth)
2. **Personal Access Token (PAT)** (new Shortcuts auth)

```
PAT Storage: User settings (refreshable; stored per-user)
PAT Format: sb_pat_<32_random_chars>
Usage: Authorization: Bearer <token> (same header for both auth types)
Validation: Token prefix detection → secrets.compare_digest() for PAT, JWT validation for Supabase
```

**Rationale:**
- ✅ **Reuse existing infrastructure** - All endpoints work with PAT, zero duplication
- ✅ **Single auth dependency** - `verify_bearer_token` supports both token types
- ✅ **Simple for Shortcuts** - Just use `Bearer sb_pat_xxx` header like JWT
- ✅ **Personal use optimized** - PAT stored in user settings, maps to a single user_id
- ✅ **Future-proof** - Can add more token types later without breaking changes

### Request Flow

```
Apple Shortcut
    ↓
[HTTP POST with Bearer sb_pat_xxx]
    ↓
sideBar API Endpoint (existing or enhanced)
    ↓
verify_bearer_token (detects PAT, validates)
    ↓
Existing Service Layer (NotesService, WebsitesService, etc.)
    ↓
Database + R2 Storage
    ↓
[Optional] Trigger Webhooks
    ↓
Other Apple Shortcuts
```

**Key Insight:** Minimal new endpoints - reuse existing APIs wherever possible, with PAT support.

---

## API Endpoints

### Strategy: Reuse + Enhance Existing Endpoints

**Key Changes:**
1. ✅ **Enhance existing endpoints** with optional parameters for Shortcuts
2. ✅ **Unified auth** - All endpoints support PAT via `verify_bearer_token`
3. 🆕 **Minimal new endpoints** - Only for features not covered by existing API
4. ✅ **Backward compatible** - Existing UI/JWT auth continues to work

---

### Quick Capture Endpoints (Enhanced Existing)

#### **Scratchpad** - `POST /api/scratchpad` (ENHANCED)
Existing endpoint enhanced with prepend-with-divider behavior for Shortcuts.

```http
POST /api/scratchpad
Authorization: Bearer sb_pat_...  # PAT now supported!
Content-Type: application/json

{
  "content": "Text to add",
  "mode": "prepend"  # NEW: prepend with divider, append, or replace
}

Response:
{
  "success": true,
  "id": "uuid"
}
```

**Scratchpad Modes:**
- `"prepend"` (Shortcuts/PAT only): Add to TOP with `___` divider
  ```markdown
  # ✏️ Scratchpad

  [NEW CONTENT]

  ___

  [EXISTING CONTENT]
  ```
- `"append"`: Add to bottom (default)
- `"replace"`: Replace all content (existing behavior)

**Changes:**
- Add `mode` parameter with prepend-divider logic
- Default to `"append"` globally
- Force `"prepend"` when PAT auth is detected (unless `mode` is explicitly set)
- Already supports PAT via enhanced `verify_bearer_token`

---

#### **Notes** - `POST /api/notes` (ENHANCED)
Existing endpoint enhanced with `title` parameter.

```http
POST /api/notes
Authorization: Bearer sb_pat_...  # PAT now supported!
Content-Type: application/json

{
  "title": "Note title",  # NEW: optional explicit title
  "content": "Markdown content",
  "folder": "folder/path"  # Existing optional parameter
}

Response:
{
  "id": "uuid",
  "title": "Note title",
  "content": "...",
  "folder": "folder/path",
  "created_at": "2025-01-03T10:00:00Z"
}
```

**Changes:**
- Add optional `title` parameter (store in DB only)
- H1 injection happens at render/export time, not on write
- Already supports PAT via enhanced `verify_bearer_token`

---

#### **Websites** - `POST /api/websites/quick-save` (NEW LIGHTWEIGHT ENDPOINT)
New simplified endpoint alongside existing `/api/websites/save` (skill-based).

```http
POST /api/websites/quick-save
Authorization: Bearer sb_pat_...
Content-Type: application/json

{
  "url": "https://example.com/article",
  "title": "Optional title"  # Auto-fetched via Jina if omitted
}

Response:
{
  "success": true,
  "data": {
    "job_id": "uuid"
  }
}
```

**Implementation:**
- Extract Jina fetching logic to `JinaService`
- Direct `WebsitesService.upsert_website()` call (no skill executor overhead)
- Keep existing `/api/websites/save` for UI (skill-based, backward compatible)
- Fail the request if Jina fetch fails (do not save empty content)
- Return `202 Accepted` with a `job_id`; completion is async.
- Provide a status endpoint for job completion (polling or webhook-triggered updates).

---

---

## V1 Implementation Summary

**Endpoints to Implement:**
1. ✅ Enhanced `/api/scratchpad` - Prepend with divider mode for PAT/Shortcuts (append default) (complete)
2. ✅ Enhanced `/api/notes` - Optional title parameter (complete)
3. ✅ New `/api/websites/quick-save` - Lightweight website saving (complete)
4. ✅ New `/api/ingestion/quick-upload` - Multipart file upload into ingestion (complete)

**Total New Endpoints:** 1 (just websites!)
**Total Enhanced Endpoints:** 2 (scratchpad, notes)
**Total Implementation Time:** ~3 hours

---

## Future Development Ideas

### Chat with sideBar

**Why Future:** Chat requires non-streaming endpoint implementation and conversation management complexity. Focus v1 on quick capture only.

**Endpoint:** `POST /api/chat/send`

```http
POST /api/chat/send
Authorization: Bearer sb_pat_...
Content-Type: application/json

{
  "message": "Question for Claude",
  "conversation_id": "uuid",  # Optional - creates new if empty
  "return_response": true     # Optional - wait for Claude response
}

Response:
{
  "success": true,
  "data": {
    "conversation_id": "uuid",
    "message_id": "uuid",
    "response": {
      "content": "Claude's response text",
      "message_id": "uuid"
    }
  }
}
```

**Implementation:**
- Reuse `ClaudeClient` for non-streaming requests
- Create conversation if needed
- Optional blocking wait for response (for Siri voice workflows)

---

### Note Templates

**Why Future:** Templates add significant complexity (database tables, rendering engine, CRUD endpoints). V1 focuses on simple quick capture.

**Schema:** See "Future Schema (Templates & Webhooks)" below.

**Endpoints:**
- `GET /api/shortcuts/templates` - List templates
- `POST /api/shortcuts/templates` - Create template
- `POST /api/shortcuts/notes/from-template` - Create note from template

**Example Use Case:**
```
Template: "meeting_notes"
Variables: {title, attendees, discussion, action_items}
Result: Structured meeting note with consistent format
```

---

### Webhooks (Two-Way Automation)

**Why Future:** Webhooks require event system, payload rendering, and external HTTP calls. Not essential for v1 quick capture.

**Schema:** See "Future Schema (Templates & Webhooks)" below.

**Supported Events:**
- `note_created`, `note_updated`, `note_deleted`
- `website_saved`, `website_deleted`
- `scratchpad_updated`
- `conversation_created`, `chat_message_sent`

**Use Cases:**
- Auto-export notes to Things 3
- Trigger backup when important note created
- Send notifications to other apps
- Cross-app automation workflows

---

### Future Schema (Templates & Webhooks)

#### Shortcut Templates

```sql
CREATE TABLE shortcut_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  name TEXT NOT NULL UNIQUE,  -- "meeting_notes", "weekly_review"
  type TEXT NOT NULL,  -- "note", "scratchpad", "chat_prompt"
  template TEXT NOT NULL,  -- Handlebars-style: "# {{title}}\n{{content}}"
  variables JSONB NOT NULL,  -- Variable schema and defaults
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_templates_user ON shortcut_templates(user_id);
CREATE INDEX idx_templates_name ON shortcut_templates(user_id, name);
```

**Example template record:**
```json
{
  "name": "meeting_notes",
  "type": "note",
  "template": "# Meeting: {{title}}\n\n**Date:** {{date}}\n**Time:** {{time}}\n**Attendees:**\n{{attendees}}\n\n## Discussion\n{{discussion}}\n\n## Action Items\n{{action_items}}",
  "variables": {
    "title": {
      "type": "text",
      "required": true,
      "default": null
    },
    "date": {
      "type": "date",
      "required": false,
      "default": "{{now}}"
    },
    "time": {
      "type": "time",
      "required": false,
      "default": "{{time}}"
    },
    "attendees": {
      "type": "list",
      "required": false,
      "default": []
    },
    "discussion": {
      "type": "text",
      "required": false,
      "default": ""
    },
    "action_items": {
      "type": "list",
      "required": false,
      "default": []
    }
  }
}
```

#### Webhooks

```sql
CREATE TABLE shortcut_webhooks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  name TEXT NOT NULL,
  event TEXT NOT NULL,  -- "note_created", "website_saved", etc.
  callback_url TEXT NOT NULL,  -- "shortcuts://run-shortcut?name=MyShortcut"
  payload_template JSONB,  -- Custom payload structure
  enabled BOOLEAN DEFAULT true,
  last_triggered_at TIMESTAMP,
  trigger_count INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_webhooks_user_event ON shortcut_webhooks(user_id, event, enabled);
```

**Supported Events:**
```python
class WebhookEvent:
    NOTE_CREATED = "note_created"
    NOTE_UPDATED = "note_updated"
    NOTE_DELETED = "note_deleted"
    WEBSITE_SAVED = "website_saved"
    WEBSITE_DELETED = "website_deleted"
    SCRATCHPAD_UPDATED = "scratchpad_updated"
    CONVERSATION_CREATED = "conversation_created"
    CONVERSATION_ENDED = "conversation_ended"
    CHAT_MESSAGE_SENT = "chat_message_sent"
```

---

### Management UI

**Why Future:** Templates/webhooks UI can wait; V1 only needs the PAT management UI.

**Features:**
- Template CRUD interface
- Webhook CRUD interface
- Usage statistics

---

### Advanced Template Features

- Conditional sections (if variable exists)
- Loops (for lists)
- Date math (`{{now + 7 days}}`)
- Template inheritance
- Custom helper functions

---

### Webhook Improvements

- Retry logic with exponential backoff
- Webhook logs/history
- Test webhook UI
- Webhook filters (only trigger if condition met)
- Rate limiting per webhook

---

### Additional Endpoints

- Batch operations (multiple items in one request)
- Search shortcuts
- File upload endpoint
- Read/get endpoints (retrieve data)
- Smart categorization with AI

---

## Implementation Details

### File Structure

```
backend/
  api/
    auth.py                 # ENHANCED: Add PAT support to verify_bearer_token
    routers/
      settings.py           # ENHANCED: PAT create/refresh endpoint
      scratchpad.py         # ENHANCED: Add mode parameter
      notes.py              # ENHANCED: Add title parameter
      websites.py           # ENHANCED: Add POST /api/websites (lightweight)
    services/
      jina_service.py       # NEW: Extract Jina fetching from skill
      user_settings_service.py  # ENHANCED: Store PAT in user settings

frontend/
  src/
    lib/
      components/
        settings/
          shortcuts/
            ShortcutsSettings.svelte     # NEW: Token management UI

Future (Phase 3+):
- `backend/api/routers/shortcuts.py` (templates/webhooks)
- `backend/api/services/template_service.py`
- `backend/api/services/webhook_service.py`
- `backend/api/models/shortcut_template.py`
- `backend/api/models/shortcut_webhook.py`
- Alembic migrations for templates/webhooks
- Templates/Webhooks UI components
```

### Changes Summary

**V1 Changes:**
- `backend/api/auth.py` - Add PAT detection and validation
- `backend/api/routers/settings.py` - Add PAT create/refresh endpoint
- `backend/api/services/user_settings_service.py` - Store PAT in user settings
- `backend/api/routers/scratchpad.py` - Add mode parameter
- `backend/api/routers/notes.py` - Add title parameter
- `backend/api/routers/websites.py` - Add lightweight POST endpoint
- `backend/api/services/jina_service.py` - Extracted Jina logic
- `frontend/src/lib/components/settings/shortcuts/ShortcutsSettings.svelte` - PAT management UI

**Future (Phase 3+):**
- `backend/api/routers/shortcuts.py` - Templates & webhooks only
- `backend/api/services/template_service.py` - Template rendering
- `backend/api/services/webhook_service.py` - Webhook triggers
- `backend/api/models/shortcut_template.py` - Template model
- `backend/api/models/shortcut_webhook.py` - Webhook model
- Alembic migrations for templates/webhooks
- `backend/api/routers/chat.py` - Optional non-streaming chat endpoint

---

### Authentication (V1)

- PAT stored in user settings and managed via Settings UI (refreshable/regenerable).
- `verify_bearer_token` accepts JWT or PAT; PATs are stored plaintext (single active token per user) and looked up by token in user settings (DB) with constant-time comparison.
- Consider caching PAT lookups per process to avoid a DB read on every request.

### Template Rendering Service

**File: `backend/api/services/template_service.py`**

```python
"""Template rendering for shortcuts."""
import re
from datetime import datetime
from typing import Dict, Any, List

class TemplateService:
    """Render Handlebars-style templates with variables."""

    # Special variables auto-populated
    SPECIAL_VARS = {
        'now': lambda: datetime.now().strftime('%Y-%m-%d'),
        'time': lambda: datetime.now().strftime('%H:%M'),
        'date': lambda: datetime.now().strftime('%B %d, %Y'),
        'datetime': lambda: datetime.now().isoformat(),
        'timestamp': lambda: int(datetime.now().timestamp())
    }

    @staticmethod
    def render(template: str, variables: Dict[str, Any]) -> str:
        """Render template with variables.

        Args:
            template: Template string with {{variable}} placeholders
            variables: Dictionary of variable values

        Returns:
            Rendered template string

        Example:
            >>> template = "# {{title}}\n{{content}}"
            >>> variables = {"title": "Hello", "content": "World"}
            >>> TemplateService.render(template, variables)
            "# Hello\nWorld"
        """
        # Evaluate special variables
        special_values = {
            key: func() for key, func in TemplateService.SPECIAL_VARS.items()
        }

        # Merge variables (user vars override special vars)
        all_vars = {**special_values, **variables}

        # Replace {{variable}} with value
        def replace_var(match):
            var_name = match.group(1)
            value = all_vars.get(var_name, '')

            # Format lists as markdown list
            if isinstance(value, list):
                if not value:
                    return ''
                return '\n'.join(f'- {item}' for item in value)

            return str(value)

        return re.sub(r'\{\{(\w+)\}\}', replace_var, template)

    @staticmethod
    def validate_variables(
        template: str,
        variables: Dict[str, Any],
        schema: Dict[str, Dict]
    ) -> List[str]:
        """Validate that required variables are provided.

        Args:
            template: Template string
            variables: Provided variables
            schema: Variable schema with 'required' field

        Returns:
            List of error messages (empty if valid)
        """
        errors = []

        for var_name, var_schema in schema.items():
            if var_schema.get('required', False):
                if var_name not in variables:
                    # Check if variable is a special var
                    if var_name not in TemplateService.SPECIAL_VARS:
                        errors.append(f"Required variable '{var_name}' not provided")

        return errors
```

### Webhook Triggering Service

**File: `backend/api/services/webhook_service.py`**

```python
"""Webhook service for triggering shortcuts."""
import json
import logging
import urllib.parse
from datetime import datetime
from typing import Any, Dict
import httpx
from sqlalchemy.orm import Session
from api.models.shortcut_webhook import ShortcutWebhook

logger = logging.getLogger(__name__)

class WebhookService:
    """Service for managing and triggering webhooks."""

    @staticmethod
    async def trigger(
        user_id: str,
        event: str,
        payload: Dict[str, Any],
        db: Session
    ) -> int:
        """Trigger all webhooks for this event.

        Args:
            user_id: User ID
            event: Event name (e.g., "note_created")
            payload: Event payload data
            db: Database session

        Returns:
            Number of webhooks triggered
        """
        webhooks = db.query(ShortcutWebhook).filter(
            ShortcutWebhook.user_id == user_id,
            ShortcutWebhook.event == event,
            ShortcutWebhook.enabled == True
        ).all()

        triggered = 0
        for webhook in webhooks:
            try:
                await WebhookService._send_webhook(webhook, payload, db)
                triggered += 1
            except Exception as e:
                logger.error(f"Webhook {webhook.id} failed: {e}")

        return triggered

    @staticmethod
    async def _send_webhook(
        webhook: ShortcutWebhook,
        payload: Dict[str, Any],
        db: Session
    ):
        """Send individual webhook."""
        # Render payload using template
        rendered_payload = WebhookService._render_payload(
            webhook.payload_template,
            payload
        )

        # Handle shortcuts:// URLs specially
        if webhook.callback_url.startswith('shortcuts://'):
            # For Apple Shortcuts, we can't actually trigger them from server
            # This is for documentation - actual triggering happens client-side
            # Just log for now
            logger.info(f"Webhook {webhook.id} ready: {webhook.callback_url}")
        else:
            # HTTP webhook
            async with httpx.AsyncClient(timeout=10.0) as client:
                await client.post(
                    webhook.callback_url,
                    json=rendered_payload,
                    headers={'Content-Type': 'application/json'}
                )

        # Update webhook metadata
        webhook.last_triggered_at = datetime.now()
        webhook.trigger_count += 1
        db.commit()

    @staticmethod
    def _render_payload(
        template: Dict[str, Any],
        data: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Render payload template with data.

        Args:
            template: Payload template with {{path.to.value}} placeholders
            data: Source data

        Returns:
            Rendered payload
        """
        if not template:
            return data

        rendered = {}
        for key, value in template.items():
            if isinstance(value, str) and '{{' in value:
                # Extract variable path: {{note.title}} -> ['note', 'title']
                import re
                match = re.search(r'\{\{(.+?)\}\}', value)
                if match:
                    path = match.group(1).split('.')
                    rendered[key] = WebhookService._get_nested_value(data, path)
                else:
                    rendered[key] = value
            elif isinstance(value, dict):
                rendered[key] = WebhookService._render_payload(value, data)
            else:
                rendered[key] = value

        return rendered

    @staticmethod
    def _get_nested_value(data: Dict[str, Any], path: List[str]) -> Any:
        """Get nested value from data using path.

        Example:
            data = {"note": {"title": "Hello"}}
            path = ["note", "title"]
            returns "Hello"
        """
        current = data
        for key in path:
            if isinstance(current, dict):
                current = current.get(key)
            else:
                return None
        return current
```

### Integration into Existing Services

**Example: Notes Service**

**File: `backend/api/services/notes_service.py`**

```python
# Add at top
from api.services.webhook_service import WebhookService

# In create_note function:
async def create_note(
    db: Session,
    user_id: str,
    title: str,
    content: str,
    folder_id: Optional[str] = None
) -> Note:
    """Create a new note."""
    # ... existing code ...

    note = Note(
        user_id=user_id,
        title=title,
        content=content,
        folder_id=folder_id
    )
    db.add(note)
    db.commit()
    db.refresh(note)

    # NEW: Trigger webhooks
    await WebhookService.trigger(
        user_id=user_id,
        event="note_created",
        payload={
            "note": {
                "id": str(note.id),
                "title": note.title,
                "content": note.content,
                "folder_id": str(note.folder_id) if note.folder_id else None,
                "created_at": note.created_at.isoformat()
            }
        },
        db=db
    )

    return note
```

Apply similar pattern to:
- `websites_service.py` → `website_saved` event
- `scratchpad_service.py` → `scratchpad_updated` event
- `chat_service.py` → `conversation_created`, `chat_message_sent` events

### Shortcuts Router

**File: `backend/api/routers/shortcuts.py`**

```python
"""Shortcuts API endpoints."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, List, Dict, Any

from api.db.session import get_db
from api.db.dependencies import get_current_user_id
from api.services.shortcuts_auth import verify_shortcuts_token
from api.services.template_service import TemplateService
from api.services.webhook_service import WebhookService
from api.services.scratchpad_service import ScratchpadService
from api.services.websites_service import WebsitesService
from api.services.notes_service import NotesService
from api.models.shortcut_template import ShortcutTemplate
from api.models.shortcut_webhook import ShortcutWebhook

router = APIRouter(prefix="/shortcuts", tags=["shortcuts"])

# Request models
class ScratchpadRequest(BaseModel):
    content: str
    mode: str = "append"  # append, prepend, replace

class WebsiteRequest(BaseModel):
    url: str
    title: Optional[str] = None
    note: Optional[str] = None

class NoteRequest(BaseModel):
    title: str
    content: str
    folder_id: Optional[str] = None

class ChatRequest(BaseModel):
    message: str
    conversation_id: Optional[str] = None
    return_response: bool = False

class TemplateRequest(BaseModel):
    name: str
    type: str
    template: str
    variables: Dict[str, Any]

class NoteFromTemplateRequest(BaseModel):
    template_name: str
    variables: Dict[str, Any]
    folder_id: Optional[str] = None

class WebhookRequest(BaseModel):
    name: str
    event: str
    callback_url: str
    payload_template: Optional[Dict[str, Any]] = None

# Endpoints
@router.post("/scratchpad")
async def add_to_scratchpad(
    request: ScratchpadRequest,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: None = Depends(verify_shortcuts_token)
):
    """Add content to scratchpad."""
    await ScratchpadService.update_scratchpad(
        db, user_id, request.content, request.mode
    )
    return {
        "success": True,
        "message": "Added to scratchpad",
        "data": {"content_length": len(request.content)}
    }

@router.post("/websites")
async def save_website(
    request: WebsiteRequest,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: None = Depends(verify_shortcuts_token)
):
    """Save website to collection."""
    website = await WebsitesService.save_website(
        db, user_id, request.url, request.title, request.note
    )
    return {
        "success": True,
        "message": "Website saved",
        "data": {
            "id": str(website.id),
            "title": website.title,
            "url": website.url
        }
    }

@router.post("/notes")
async def create_note(
    request: NoteRequest,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: None = Depends(verify_shortcuts_token)
):
    """Create a new note."""
    note = await NotesService.create_note(
        db, user_id, request.title, request.content, request.folder_id
    )
    return {
        "success": True,
        "message": "Note created",
        "data": {
            "id": str(note.id),
            "title": note.title,
            "folder_id": str(note.folder_id) if note.folder_id else None
        }
    }

@router.post("/notes/from-template")
async def create_note_from_template(
    request: NoteFromTemplateRequest,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: None = Depends(verify_shortcuts_token)
):
    """Create note from template."""
    # Get template
    template = db.query(ShortcutTemplate).filter(
        ShortcutTemplate.user_id == user_id,
        ShortcutTemplate.name == request.template_name
    ).first()

    if not template:
        raise HTTPException(404, "Template not found")

    # Validate variables
    errors = TemplateService.validate_variables(
        template.template,
        request.variables,
        template.variables
    )
    if errors:
        raise HTTPException(400, ", ".join(errors))

    # Render template
    content = TemplateService.render(template.template, request.variables)

    # Extract title from template or use first line
    title = request.variables.get('title', content.split('\n')[0].replace('#', '').strip())

    # Create note
    note = await NotesService.create_note(
        db, user_id, title, content, request.folder_id
    )

    return {
        "success": True,
        "message": "Note created from template",
        "data": {
            "id": str(note.id),
            "title": note.title,
            "content": content
        }
    }

# Template endpoints
@router.get("/templates")
async def list_templates(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: None = Depends(verify_shortcuts_token)
):
    """List all templates."""
    templates = db.query(ShortcutTemplate).filter(
        ShortcutTemplate.user_id == user_id
    ).all()

    return {
        "templates": [
            {
                "id": str(t.id),
                "name": t.name,
                "type": t.type,
                "variables": t.variables
            }
            for t in templates
        ]
    }

@router.post("/templates")
async def create_template(
    request: TemplateRequest,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: None = Depends(verify_shortcuts_token)
):
    """Create new template."""
    template = ShortcutTemplate(
        user_id=user_id,
        name=request.name,
        type=request.type,
        template=request.template,
        variables=request.variables
    )
    db.add(template)
    db.commit()
    db.refresh(template)

    return {
        "success": True,
        "data": {
            "id": str(template.id),
            "name": template.name
        }
    }

# Webhook endpoints
@router.get("/webhooks")
async def list_webhooks(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: None = Depends(verify_shortcuts_token)
):
    """List all webhooks."""
    webhooks = db.query(ShortcutWebhook).filter(
        ShortcutWebhook.user_id == user_id
    ).all()

    return {
        "webhooks": [
            {
                "id": str(w.id),
                "name": w.name,
                "event": w.event,
                "callback_url": w.callback_url,
                "enabled": w.enabled,
                "trigger_count": w.trigger_count,
                "last_triggered_at": w.last_triggered_at.isoformat() if w.last_triggered_at else None
            }
            for w in webhooks
        ]
    }

@router.post("/webhooks")
async def create_webhook(
    request: WebhookRequest,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: None = Depends(verify_shortcuts_token)
):
    """Create new webhook."""
    webhook = ShortcutWebhook(
        user_id=user_id,
        name=request.name,
        event=request.event,
        callback_url=request.callback_url,
        payload_template=request.payload_template or {}
    )
    db.add(webhook)
    db.commit()
    db.refresh(webhook)

    return {
        "success": True,
        "data": {
            "id": str(webhook.id),
            "name": webhook.name
        }
    }

@router.delete("/webhooks/{webhook_id}")
async def delete_webhook(
    webhook_id: str,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: None = Depends(verify_shortcuts_token)
):
    """Delete webhook."""
    webhook = db.query(ShortcutWebhook).filter(
        ShortcutWebhook.id == webhook_id,
        ShortcutWebhook.user_id == user_id
    ).first()

    if not webhook:
        raise HTTPException(404, "Webhook not found")

    db.delete(webhook)
    db.commit()

    return {"success": True, "message": "Webhook deleted"}

@router.put("/webhooks/{webhook_id}/toggle")
async def toggle_webhook(
    webhook_id: str,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: None = Depends(verify_shortcuts_token)
):
    """Toggle webhook enabled state."""
    webhook = db.query(ShortcutWebhook).filter(
        ShortcutWebhook.id == webhook_id,
        ShortcutWebhook.user_id == user_id
    ).first()

    if not webhook:
        raise HTTPException(404, "Webhook not found")

    webhook.enabled = not webhook.enabled
    db.commit()

    return {"success": True, "enabled": webhook.enabled}
```

**Register router in `main.py`:**
```python
from api.routers import shortcuts

app.include_router(shortcuts.router, prefix="/api")
```

---

## Configuration (V1)

- **PAT management:** Generate/refresh the PAT in the Settings UI and store it in user settings (DB). Shortcuts use that token in the Authorization header.
- **Jina API key:** Keep `JINA_API_KEY` in env/config for website fetching.

---

## Example Apple Shortcuts

**PAT:** Copy the token from Settings → Shortcuts in sideBar and use it in the Authorization header.

### 1. Add to Scratchpad (Top with Divider)

```
Name: Add to sideBar
Input: Text, URLs, or Ask Each Time
Trigger: Share Sheet, Siri

Actions:
1. Get input
2. URL: https://yourdomain.com/api/scratchpad
   Method: POST
   Headers:
     Authorization: Bearer sb_pat_xxx  # Your PAT token
     Content-Type: application/json
   Body: {"content": "[Input]", "mode": "prepend"}
3. If Success:
     Show notification "Added to scratchpad ✓"
   Otherwise:
     Show alert "Error: [Error Message]"
```

**Result:**
```markdown
# ✏️ Scratchpad

[YOUR NEW CONTENT]

___

[EXISTING SCRATCHPAD CONTENT]
```

**Note:** Uses existing `/api/scratchpad` endpoint with new prepend mode!

---

### 2. Save Website

```
Name: Save to sideBar
Input: URLs from Share Sheet
Trigger: Share Sheet (Safari)

Actions:
1. Get URLs from input
2. URL: https://yourdomain.com/api/websites
   Method: POST
   Headers:
     Authorization: Bearer sb_pat_xxx  # Your PAT token
     Content-Type: application/json
   Body: {"url": "[URLs]"}  # Title auto-fetched by Jina
3. Show notification "Saved ✓"
```

**Note:** Uses new lightweight `/api/websites` endpoint (not `/save`)

---

### 3. Quick Note

```
Name: Quick Note
Input: Text
Trigger: Share Sheet, Siri

Actions:
1. Ask for input "Note title?"
2. Text → Set variable [Title]
3. Ask for input "Note content (or dictate)?"
4. Text → Set variable [Content]
5. URL: https://yourdomain.com/api/notes
   Method: POST
   Headers:
     Authorization: Bearer sb_pat_xxx  # Your PAT token
     Content-Type: application/json
   Body: {
     "title": "[Title]",
     "content": "[Content]"
   }
6. Show notification "Note created ✓"
```

**Note:** Uses existing `/api/notes` endpoint with new `title` parameter!

---


---

## V1 Implementation Plan

### Phase 1: Foundation & Auth (1.5 hours)

**Goal:** Unified auth working, PAT tokens functional

1. **Enhance `auth.py`** - Add PAT detection and validation (30 min)
   - Token prefix check (`sb_pat_`)
   - Constant-time comparison
   - User ID mapping from user settings (DB)
2. **Add PAT storage to user settings** (30 min)
   - Create/refresh endpoint in Settings API
   - Store token hash or plaintext (decide) + user_id
3. **Add Settings UI** for PAT (20 min)
   - Show current token (copy)
   - Regenerate/rotate token
4. **Test PAT auth** with existing endpoints (20 min)

**Deliverable:** ✅ Can authenticate with PAT on ANY existing endpoint

---

### Phase 2: Quick Capture (1.5 hours)

**Goal:** All v1 capture methods working

1. **Enhance `/api/scratchpad`** - Add prepend-with-divider mode (30 min)
   - Prepend logic: new content + `\n\n___\n\n` + existing content
   - Default to append; force prepend when PAT auth is detected
   - Keep title at top
   - Test with Shortcuts
2. **Enhance `/api/notes`** - Add optional title parameter (20 min)
   - Store title in DB only
   - Inject H1 at render/export time
   - Test with Shortcuts
3. **Create `JinaService`** - Extract from skill (30 min)
   - Fail request if fetch fails (no null-content saves)
   - Fetch markdown from Jina.ai
   - Parse metadata (title, published_at)
4. **Create `/api/websites/quick-save`** - Lightweight endpoint (30 min)
   - Use JinaService + WebsitesService.upsert_website()
   - No skill executor overhead
   - Test with Shortcuts
5. **Create `/api/ingestion/quick-upload`** - Multipart upload endpoint (45 min)
   - Accept `multipart/form-data` with `file`
   - Create ingestion job + enqueue worker
   - Return `202` with `job_id` and `file_id`
   - Remove original file after ingestion completes (match UI behavior)

**Deliverable:** ✅ Can add to scratchpad (prepend with divider via PAT/Shortcuts), create notes, save websites, and ingest files from iPhone

---

## V1 Total Time: ~3 hours 🚀

**What You Get:**
- ✅ PAT authentication on all endpoints
- ✅ Scratchpad quick capture (prepend with divider via PAT/Shortcuts)
- ✅ Notes quick capture (with optional title)
- ✅ Website saving (auto-fetch content)
- ✅ Full Siri integration for all features
- ✅ 3 working Apple Shortcuts examples

**What's Deferred to Future:**
- 💬 Chat with sideBar
- 📋 Note templates
- 🔗 Webhooks
- 🎨 Templates/Webhooks management UI

---

## V1 Success Criteria

✅ **Authentication:** Can authenticate with PAT on all existing endpoints
✅ **Scratchpad:** Can add content via Siri, using prepend-with-divider for PAT/Shortcuts
✅ **Notes:** Can create quick notes with optional title via Siri
✅ **Websites:** Can save websites from Safari share sheet with auto-fetched content
✅ **Files:** Can upload a file from Shortcuts and see it ingested without keeping the original
✅ **Cross-device:** All shortcuts work on iPhone, iPad, Mac, Apple Watch
✅ **Voice-first:** All capture flows work hands-free via Siri
