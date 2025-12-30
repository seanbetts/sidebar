# Apple Shortcuts Integration Plan

## Ambition

Enable seamless integration between sideBar and Apple Shortcuts for rapid capture and automation workflows. Personal use focused - simple, powerful, no over-engineering.

**Core Philosophy:**
- Quick capture from any Apple device (iPhone, iPad, Mac, Apple Watch)
- Voice-first workflows via Siri
- Template-driven structured content creation
- Webhook-powered automation between sideBar and other apps
- Zero-friction daily usage

**Key Capabilities:**
1. **Quick Capture:** Add to scratchpad, save websites, create notes via Shortcuts
2. **Templates:** Pre-structured note formats (meeting notes, daily logs, etc.)
3. **Webhooks:** Trigger Shortcuts when events happen in sideBar (two-way automation)
4. **Voice Integration:** Full Siri support for hands-free operation

---

## Architecture Overview

### Authentication Model

**Single Personal Access Token** (no complex token management)

```
Storage: Environment variable or user_settings table
Format: sb_pat_<32_random_chars>
Usage: Bearer token in Authorization header
Validation: Simple secrets.compare_digest()
```

**Rationale:**
- Personal use only - one user, one token
- No expiry, revocation, or scope management needed
- Can regenerate if compromised
- Stored securely in iCloud Keychain via Shortcuts

### Request Flow

```
Apple Shortcut
    ↓
[HTTP POST with Bearer token]
    ↓
sideBar API Endpoint
    ↓
Shortcuts Auth Middleware
    ↓
Existing Service Layer
    ↓
Database + R2 Storage
    ↓
[Optional] Trigger Webhooks
    ↓
Other Apple Shortcuts
```

---

## Database Schema

### Shortcut Templates

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

### Webhooks

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

## API Endpoints

### Authentication Setup

**Get/Regenerate Token**
```http
GET /api/shortcuts/token
Authorization: Bearer <supabase_jwt>

Response:
{
  "token": "sb_pat_a1b2c3d4e5f6...",
  "created_at": "2025-01-03T10:00:00Z"
}
```

```http
POST /api/shortcuts/token/regenerate
Authorization: Bearer <supabase_jwt>

Response:
{
  "token": "sb_pat_newtoken123...",
  "created_at": "2025-01-03T11:00:00Z"
}
```

### Quick Capture Endpoints

**Scratchpad**
```http
POST /api/shortcuts/scratchpad
Authorization: Bearer sb_pat_...
Content-Type: application/json

{
  "content": "Text to add",
  "mode": "append" | "replace" | "prepend"
}

Response:
{
  "success": true,
  "message": "Added to scratchpad",
  "data": {
    "content_length": 123
  }
}
```

**Websites**
```http
POST /api/shortcuts/websites
Authorization: Bearer sb_pat_...
Content-Type: application/json

{
  "url": "https://example.com/article",
  "title": "Optional title",  // Auto-fetched via Jina if omitted
  "note": "Optional personal note"
}

Response:
{
  "success": true,
  "message": "Website saved",
  "data": {
    "id": "uuid",
    "title": "Article Title",
    "url": "https://example.com/article"
  }
}
```

**Notes**
```http
POST /api/shortcuts/notes
Authorization: Bearer sb_pat_...
Content-Type: application/json

{
  "title": "Note title",
  "content": "Markdown content",
  "folder_id": "uuid"  // Optional
}

Response:
{
  "success": true,
  "message": "Note created",
  "data": {
    "id": "uuid",
    "title": "Note title",
    "folder_id": "uuid"
  }
}
```

**Chat**
```http
POST /api/shortcuts/chat
Authorization: Bearer sb_pat_...
Content-Type: application/json

{
  "message": "Question for Claude",
  "conversation_id": "uuid",  // Optional - creates new if empty
  "return_response": true  // Optional - wait for Claude response
}

Response (if return_response=false):
{
  "success": true,
  "message": "Message sent",
  "data": {
    "conversation_id": "uuid",
    "message_id": "uuid"
  }
}

Response (if return_response=true):
{
  "success": true,
  "message": "Message sent",
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

### Template Endpoints

**List Templates**
```http
GET /api/shortcuts/templates
Authorization: Bearer sb_pat_...

Response:
{
  "templates": [
    {
      "id": "uuid",
      "name": "meeting_notes",
      "type": "note",
      "variables": {...}
    }
  ]
}
```

**Create Template**
```http
POST /api/shortcuts/templates
Authorization: Bearer sb_pat_...
Content-Type: application/json

{
  "name": "meeting_notes",
  "type": "note",
  "template": "# Meeting: {{title}}\n...",
  "variables": {
    "title": {"type": "text", "required": true}
  }
}

Response:
{
  "success": true,
  "data": {
    "id": "uuid",
    "name": "meeting_notes"
  }
}
```

**Use Template**
```http
POST /api/shortcuts/notes/from-template
Authorization: Bearer sb_pat_...
Content-Type: application/json

{
  "template_name": "meeting_notes",
  "variables": {
    "title": "Weekly Standup",
    "attendees": ["Alice", "Bob"],
    "discussion": "Discussed Q1 goals"
  },
  "folder_id": "uuid"  // Optional
}

Response:
{
  "success": true,
  "message": "Note created from template",
  "data": {
    "id": "uuid",
    "title": "Meeting: Weekly Standup",
    "content": "# Meeting: Weekly Standup\n..."
  }
}
```

### Webhook Endpoints

**List Webhooks**
```http
GET /api/shortcuts/webhooks
Authorization: Bearer sb_pat_...

Response:
{
  "webhooks": [
    {
      "id": "uuid",
      "name": "Export to Things",
      "event": "note_created",
      "callback_url": "shortcuts://...",
      "enabled": true,
      "trigger_count": 42,
      "last_triggered_at": "2025-01-03T10:00:00Z"
    }
  ]
}
```

**Create Webhook**
```http
POST /api/shortcuts/webhooks
Authorization: Bearer sb_pat_...
Content-Type: application/json

{
  "name": "Export to Things",
  "event": "note_created",
  "callback_url": "shortcuts://run-shortcut?name=ExportNote",
  "payload_template": {
    "title": "{{note.title}}",
    "content": "{{note.content}}",
    "id": "{{note.id}}"
  }
}

Response:
{
  "success": true,
  "data": {
    "id": "uuid",
    "name": "Export to Things"
  }
}
```

**Delete Webhook**
```http
DELETE /api/shortcuts/webhooks/{webhook_id}
Authorization: Bearer sb_pat_...

Response:
{
  "success": true,
  "message": "Webhook deleted"
}
```

**Toggle Webhook**
```http
PUT /api/shortcuts/webhooks/{webhook_id}/toggle
Authorization: Bearer sb_pat_...

Response:
{
  "success": true,
  "enabled": false
}
```

---

## Implementation Details

### File Structure

```
backend/
  api/
    routers/
      shortcuts.py          # NEW: All shortcuts endpoints
    services/
      template_service.py   # NEW: Template rendering
      webhook_service.py    # NEW: Webhook triggering
      shortcuts_auth.py     # NEW: Token validation
    models/
      shortcut_template.py  # NEW: Template model
      shortcut_webhook.py   # NEW: Webhook model
    alembic/
      versions/
        YYYYMMDD_HHmm-NNN_add_shortcuts_tables.py  # NEW

frontend/
  src/
    lib/
      components/
        settings/
          shortcuts/
            ShortcutsSettings.svelte     # NEW: Token management
            TemplateManager.svelte       # NEW: Template CRUD
            WebhookManager.svelte        # NEW: Webhook CRUD
```

### Authentication Middleware

**File: `backend/api/services/shortcuts_auth.py`**

```python
"""Shortcuts API authentication."""
import secrets
from fastapi import HTTPException, Header
from api.config import settings

def verify_shortcuts_token(authorization: str = Header(None)) -> None:
    """Verify shortcuts API token from Authorization header.

    Raises:
        HTTPException: 401 if token invalid or missing
    """
    if not authorization or not authorization.startswith('Bearer '):
        raise HTTPException(
            status_code=401,
            detail="Missing or invalid Authorization header"
        )

    token = authorization.replace('Bearer ', '')

    # Compare with stored token (from env or database)
    expected_token = settings.shortcuts_api_token

    if not expected_token:
        raise HTTPException(
            status_code=500,
            detail="Shortcuts API not configured"
        )

    # Constant-time comparison to prevent timing attacks
    if not secrets.compare_digest(token, expected_token):
        raise HTTPException(
            status_code=401,
            detail="Invalid API token"
        )
```

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

## Configuration

### Environment Variables

**Add to `.env.example`:**
```bash
# Shortcuts Integration
SHORTCUTS_API_TOKEN=sb_pat_generate_a_random_32_char_string_here
```

**Add to `backend/api/config.py`:**
```python
class Settings(BaseSettings):
    # ... existing settings ...

    # Shortcuts integration
    shortcuts_api_token: str = ""

    class Config:
        env_file = ".env"
```

---

## Example Apple Shortcuts

### 1. Add to Scratchpad

```
Name: Add to sideBar
Input: Text, URLs, or Ask Each Time
Trigger: Share Sheet, Siri

Actions:
1. Get input
2. URL: https://yourdomain.com/api/shortcuts/scratchpad
   Method: POST
   Headers:
     Authorization: Bearer [Your Token]
     Content-Type: application/json
   Body: {"content": "[Input]", "mode": "append"}
3. If Success:
     Show notification "Added to scratchpad ✓"
   Otherwise:
     Show alert "Error: [Error Message]"
```

### 2. Save Website

```
Name: Save to sideBar
Input: URLs from Share Sheet
Trigger: Share Sheet (Safari)

Actions:
1. Get URLs from input
2. Get webpage details (title)
3. URL: https://yourdomain.com/api/shortcuts/websites
   Method: POST
   Headers:
     Authorization: Bearer [Your Token]
     Content-Type: application/json
   Body: {"url": "[URLs]", "title": "[Webpage Title]"}
4. Show notification "Saved ✓"
```

### 3. Meeting Notes (Template)

```
Name: Meeting Notes
Input: None
Trigger: Siri, Manual

Actions:
1. Ask for input "Meeting title?"
2. Text → Set variable [Title]
3. Ask for input "Attendees?"
4. Text → Set variable [Attendees]
5. Dictation enabled → Ask "Discussion points?"
6. Text → Set variable [Discussion]
7. URL: https://yourdomain.com/api/shortcuts/notes/from-template
   Method: POST
   Headers:
     Authorization: Bearer [Your Token]
     Content-Type: application/json
   Body: {
     "template_name": "meeting_notes",
     "variables": {
       "title": "[Title]",
       "attendees": "[Attendees]",
       "discussion": "[Discussion]"
     }
   }
8. Show notification "Meeting notes created ✓"
```

### 4. Quick Question to Claude

```
Name: Ask sideBar
Input: Text
Trigger: Siri ("Ask sideBar")

Actions:
1. Ask for input "What's your question?"
2. URL: https://yourdomain.com/api/shortcuts/chat
   Method: POST
   Headers:
     Authorization: Bearer [Your Token]
     Content-Type: application/json
   Body: {
     "message": "[Input]",
     "return_response": true
   }
3. Get response → Extract [response.content]
4. Show quick look [Response Content]
   OR Speak text [Response Content]
```

---

## Implementation Phases

### Phase 1: Foundation (MVP - 3 hours)

**Goal:** Basic quick capture working

1. Add `SHORTCUTS_API_TOKEN` to `.env.local`
2. Create `shortcuts_auth.py` middleware
3. Create basic `shortcuts.py` router with scratchpad endpoint
4. Register router in `main.py`
5. Test with one manual Shortcut

**Deliverable:** Can add text to scratchpad from iPhone

---

### Phase 2: Core Endpoints (2 hours)

**Goal:** All quick capture methods working

1. Add websites endpoint
2. Add notes endpoint
3. Add chat endpoint (with optional response wait)
4. Test all endpoints with Shortcuts

**Deliverable:** Can capture to all sections of sideBar

---

### Phase 3: Templates (4 hours)

**Goal:** Template system fully functional

1. Create database migration for `shortcut_templates`
2. Create `ShortcutTemplate` model
3. Create `TemplateService` with rendering logic
4. Add template CRUD endpoints
5. Add `notes/from-template` endpoint
6. Create 3-4 default templates
7. Test template-based note creation

**Deliverable:** Can create structured notes via templates

---

### Phase 4: Webhooks (5 hours)

**Goal:** Two-way automation working

1. Create database migration for `shortcut_webhooks`
2. Create `ShortcutWebhook` model
3. Create `WebhookService` with trigger logic
4. Add webhook CRUD endpoints
5. Integrate webhook triggers into:
   - `notes_service.py`
   - `websites_service.py`
   - `scratchpad_service.py`
6. Test webhook → Shortcut flow

**Deliverable:** Can trigger Shortcuts from sideBar events

---

### Phase 5: Polish & UI (3 hours)

**Goal:** Easy management without API calls

1. Add Shortcuts section to Settings dialog
2. Show/regenerate API token
3. Optional: Template manager UI
4. Optional: Webhook manager UI
5. Create setup guide documentation

**Deliverable:** Can manage everything from web UI

---

## Total Estimated Time: ~17 hours

**Breakdown:**
- MVP: 3 hours
- Core endpoints: 2 hours
- Templates: 4 hours
- Webhooks: 5 hours
- UI/Polish: 3 hours

---

## Success Criteria

✅ Can add to scratchpad via Siri
✅ Can save websites from Safari share sheet
✅ Can create notes with voice dictation
✅ Can create structured notes from templates
✅ Can trigger Shortcuts when notes are created
✅ Can ask Claude questions and get spoken responses
✅ Token management works from Settings UI
✅ All integrations work across iPhone, iPad, Mac

---

## Future Enhancements

### Advanced Templates
- Conditional sections (if variable exists)
- Loops (for lists)
- Date math ({{now + 7 days}})
- Template inheritance

### Webhook Improvements
- Retry logic with exponential backoff
- Webhook logs/history
- Test webhook UI
- Webhook filters (only trigger if condition met)

### Additional Endpoints
- Batch operations (multiple items in one request)
- Search shortcuts
- File upload endpoint
- Read/get endpoints (retrieve data)

### Smart Shortcuts
- Context-aware templates (location, time, focus mode)
- AI-powered categorization
- Auto-tagging based on content
- Smart scheduling (time-based triggers)
