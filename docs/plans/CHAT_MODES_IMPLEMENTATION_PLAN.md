---
title: "Chat Modes Implementation Plan for sideBar"
description: "Plan for chat modes feature scope and rollout."
---

# Chat Modes Implementation Plan for sideBar

## Executive Summary

This plan implements a per-message Chat Modes system for sideBar with five modes (Quick, Research, Planning, Brainstorming, Writing) that can be selected via UI icons, keyboard shortcuts (⌘+letter), or self-switched by the assistant. Mode behavior is enforced through orchestration (model selection, tool gating, budgets, validation) rather than just prompts.

**Key Design Decisions:**
- **Writing mode:** Per-conversation "Writing Draft" note that gets updated
- **Model selection:** Per-mode model config (Haiku for Quick, Sonnet for Research/Planning/Brainstorming, Opus for Writing)
- **Auto-switching:** Allow auto-switch with notification when user intent is clear
- **Icon layout:** Attach | Mode icons | Send (center placement)

**Principles:**
- Mode is per-message, not per-conversation
- No conversation reset when switching modes
- Mode controls model, max_tokens, temperature, allowed tools, and validation rules
- Backward compatible: existing conversations default to "quick" mode
- UI reflects both user-selected and assistant-initiated mode changes

**Total Effort:** 17-25 days

---

## Phase 1: Foundation - Type Definitions & Configuration (2-3 days)

### Objectives
- Define mode types and configurations
- Establish mode orchestration rules
- Create frontend and backend type definitions

### 1.1 Backend Type Definitions

**File: `/Users/sean/Coding/sideBar/backend/api/schemas/chat_mode.py` (NEW)**

Create core schemas:
```python
class ChatModeType(str, Enum):
    QUICK = "quick"
    RESEARCH = "research"
    PLANNING = "planning"
    BRAINSTORMING = "brainstorming"
    WRITING = "writing"

class ChatModeConfig(BaseModel):
    id: ChatModeType
    display_name: str
    icon: str
    keyboard_shortcut: str

    # Model configuration
    model: str
    temperature: float
    max_tokens: int

    # Orchestration controls
    max_tool_rounds: int
    allowed_tool_categories: Optional[List[str]] = None
    disallowed_skills: List[str] = Field(default_factory=list)

    # Validation rules
    require_sources: bool = False
    require_writing_draft: bool = False

    # Prompt injection
    system_prompt_suffix: Optional[str] = None
```

**File: `/Users/sean/Coding/sideBar/backend/api/config/chat_modes.py` (NEW)**

Define mode configurations:
```python
CHAT_MODES: dict[ChatModeType, ChatModeConfig] = {
    ChatModeType.QUICK: ChatModeConfig(
        id=ChatModeType.QUICK,
        display_name="Quick",
        icon="zap",
        keyboard_shortcut="q",
        model="claude-haiku-4-20250514",  # Fast, cheap
        temperature=1.0,
        max_tokens=2048,
        max_tool_rounds=3,
        system_prompt_suffix="You are in Quick mode. Be concise and efficient."
    ),
    ChatModeType.RESEARCH: ChatModeConfig(
        id=ChatModeType.RESEARCH,
        display_name="Research",
        icon="search",
        keyboard_shortcut="r",
        model="claude-sonnet-4-5-20250929",
        temperature=0.7,
        max_tokens=8192,
        max_tool_rounds=8,
        require_sources=True,
        system_prompt_suffix='Research mode requires "Sources:" section...'
    ),
    # ... similar configs for PLANNING, BRAINSTORMING, WRITING
}
```

**Mode Specifications:**
- **Quick:** Haiku, 2048 tokens, 3 tool rounds, fast responses
- **Research:** Sonnet, 8192 tokens, 8 tool rounds, requires sources validation
- **Planning:** Sonnet, 6144 tokens, 6 tool rounds, structured outputs
- **Brainstorming:** Sonnet, 4096 tokens, 4 tool rounds, temp=1.2 for creativity
- **Writing:** Opus, 8192 tokens, 10 tool rounds, requires draft note workflow

### 1.2 Frontend Type Definitions

**File: `/Users/sean/Coding/sideBar/frontend/src/lib/types/chatMode.ts` (NEW)**

```typescript
export type ChatModeType = 'quick' | 'research' | 'planning' | 'brainstorming' | 'writing';

export interface ChatModeConfig {
  id: ChatModeType;
  displayName: string;
  icon: string;  // lucide-svelte icon name
  keyboardShortcut: string;
  description: string;
}

export const CHAT_MODES: Record<ChatModeType, ChatModeConfig> = {
  quick: {
    id: 'quick',
    displayName: 'Quick',
    icon: 'zap',
    keyboardShortcut: '⌘Q',
    description: 'Fast responses with Haiku'
  },
  // ... other modes
};

export interface ChatModeSwitchEvent {
  type: 'mode_switch';
  mode: ChatModeType;
  reason?: string;
}
```

**Update: `/Users/sean/Coding/sideBar/frontend/src/lib/types/chat.ts`**

Add mode field to Message interface:
```typescript
export interface Message {
  // ... existing fields
  mode?: string;  // NEW: chat mode for this message
}
```

### Deliverables
- ✅ Backend chat mode schemas
- ✅ Frontend chat mode types
- ✅ Mode configurations with orchestration rules
- ✅ Updated Message interface

---

## Phase 2: Database Schema Changes (1-2 days)

### Objectives
- Add mode field to messages
- Add writing_draft_note_id to conversations
- Backfill existing messages with default mode

### 2.1 Migration: Add mode to messages

**File: `/Users/sean/Coding/sideBar/backend/api/alembic/versions/20260107_1400-028_add_message_mode.py` (NEW)**

Strategy:
1. Update all existing messages to add `mode: 'quick'`
2. No schema change needed (JSONB is flexible)
3. Future messages include mode from application code

```python
def upgrade() -> None:
    # Backfill existing messages with mode='quick'
    op.execute("""
        UPDATE conversations
        SET messages = (
            SELECT jsonb_agg(
                msg || jsonb_build_object('mode', 'quick')
            )
            FROM jsonb_array_elements(messages) AS msg
            WHERE NOT (msg ? 'mode')
        )
        WHERE messages IS NOT NULL
        AND messages != '[]'::jsonb
    """)

    # Optional: Create GIN index for mode analytics
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_conversations_messages_mode_gin
        ON conversations USING gin ((messages @> '[{"mode": "research"}]'::jsonb))
    """)
```

### 2.2 Migration: Add writing_draft_note_id

**File: `/Users/sean/Coding/sideBar/backend/api/alembic/versions/20260107_1430-029_add_writing_draft_note.py` (NEW)**

```python
def upgrade() -> None:
    op.add_column(
        'conversations',
        sa.Column(
            'writing_draft_note_id',
            UUID(as_uuid=True),
            nullable=True,
            index=True
        )
    )

    op.create_foreign_key(
        'fk_conversations_writing_draft_note',
        'conversations',
        'notes',
        ['writing_draft_note_id'],
        ['id'],
        ondelete='SET NULL'
    )
```

**Update: `/Users/sean/Coding/sideBar/backend/api/models/conversation.py`**

```python
writing_draft_note_id: Mapped[uuid.UUID | None] = mapped_column(
    UUID(as_uuid=True),
    nullable=True,
    index=True
)
```

### Deliverables
- ✅ Migration 028: Add mode to existing messages
- ✅ Migration 029: Add writing_draft_note_id FK
- ✅ Updated Conversation model
- ✅ Backfill strategy executed

---

## Phase 3: Backend Orchestration & Mode Integration (3-4 days)

### Objectives
- Accept mode parameter in chat endpoint
- Inject mode into system prompt
- Use mode config for model selection and orchestration

### 3.1 Update Chat Endpoint

**File: `/Users/sean/Coding/sideBar/backend/api/routers/chat.py`**

In `stream_chat` function:
```python
from api.schemas.chat_mode import ChatModeType
from api.config.chat_modes import get_mode_config

# Parse mode from request
mode_str = data.get("mode", "quick")
try:
    mode = ChatModeType(mode_str)
except ValueError:
    mode = ChatModeType.QUICK
mode_config = get_mode_config(mode)

# Build prompts with mode config
system_prompt, first_message_prompt = PromptContextService.build_prompts(
    # ... existing params
    mode_config=mode_config,  # NEW
)

# Pass mode config to streaming
async for event in claude_client.stream_with_tools(
    message,
    history,
    system_prompt=system_prompt,
    allowed_skills=enabled_skills,
    tool_context=tool_context,
    mode_config=mode_config,  # NEW
):
    yield event
```

### 3.2 Update Prompt Service

**File: `/Users/sean/Coding/sideBar/backend/api/services/prompt_context_service.py`**

```python
@staticmethod
def build_prompts(
    # ... existing params
    mode_config: ChatModeConfig | None = None,  # NEW
) -> tuple[str, str]:
    # ... build system_prompt ...

    # Inject mode-specific instructions
    if mode_config and mode_config.system_prompt_suffix:
        system_prompt = f"{system_prompt}\n\n<chat_mode>\n{mode_config.system_prompt_suffix}\n</chat_mode>"

    return system_prompt, first_message_prompt
```

### 3.3 Update Claude Client

**File: `/Users/sean/Coding/sideBar/backend/api/services/claude_client.py`**

```python
async def stream_with_tools(
    self,
    message: str,
    conversation_history: List[Dict[str, Any]] | None = None,
    system_prompt: str | None = None,
    allowed_skills: List[str] | None = None,
    tool_context: ToolExecutionContext | Dict[str, Any] | None = None,
    mode_config: ChatModeConfig | None = None,  # NEW
) -> AsyncIterator[Dict[str, Any]]:
    from api.config.chat_modes import get_mode_config, ChatModeType

    if mode_config is None:
        mode_config = get_mode_config(ChatModeType.QUICK)

    async for event in stream_with_tools(
        client=self.client,
        tool_mapper=self.tool_mapper,
        model=mode_config.model,  # Use mode's model
        message=message,
        conversation_history=conversation_history,
        system_prompt=system_prompt,
        allowed_skills=allowed_skills,
        tool_context=tool_context,
        mode_config=mode_config,
    ):
        yield event
```

### 3.4 Update Streaming Orchestrator

**File: `/Users/sean/Coding/sideBar/backend/api/services/claude_streaming.py`**

```python
async def stream_with_tools(
    *,
    client: Any,
    tool_mapper: Any,
    model: str,
    message: str,
    # ... existing params
    mode_config: ChatModeConfig | None = None,  # NEW
) -> AsyncIterator[Dict[str, Any]]:
    if mode_config is None:
        mode_config = get_mode_config(ChatModeType.QUICK)

    # Filter skills based on mode
    filtered_skills = allowed_skills
    if mode_config.disallowed_skills and filtered_skills is not None:
        filtered_skills = [
            s for s in filtered_skills
            if s not in mode_config.disallowed_skills
        ]

    # Use mode-specific limits
    max_rounds = mode_config.max_tool_rounds

    stream_args: Dict[str, Any] = {
        "model": mode_config.model,
        "max_tokens": mode_config.max_tokens,
        "temperature": mode_config.temperature,
        "messages": messages,
        "tools": tools,
    }

    # ... streaming loop with max_rounds instead of hardcoded 5 ...
```

### Deliverables
- ✅ Chat endpoint accepts mode parameter
- ✅ Prompt service injects mode instructions
- ✅ Claude client uses mode's model/params
- ✅ Streaming orchestrator enforces mode limits

---

## Phase 4: Mode-Specific Validation & Enforcement (2-3 days)

### Objectives
- Implement Research mode sources validation
- Implement Writing mode draft note helpers
- Validate mode requirements at response completion

### 4.1 Research Mode: Sources Validation

**File: `/Users/sean/Coding/sideBar/backend/api/services/mode_validators.py` (NEW)**

```python
class ModeValidator:
    @staticmethod
    def validate_research_sources(content: str) -> tuple[bool, Optional[str]]:
        """Validate Research mode requires Sources section."""
        # Only require sources if web search was used
        has_web_search = "web_search_tool_result" in content.lower()
        if not has_web_search:
            return True, None

        # Check for Sources header
        sources_pattern = r'(?:^|\n)#+\s*Sources:?\s*\n|(?:^|\n)Sources:?\s*\n'
        has_sources = bool(re.search(sources_pattern, content, re.MULTILINE | re.IGNORECASE))

        if not has_sources:
            return False, "Research mode requires a 'Sources:' section"

        # Validate markdown links in sources section
        sources_match = re.search(
            r'(?:^|\n)(?:#+\s*)?Sources:?\s*\n(.*?)(?:\n\n|\Z)',
            content,
            re.MULTILINE | re.IGNORECASE | re.DOTALL
        )

        if sources_match:
            sources_content = sources_match.group(1)
            markdown_links = re.findall(r'\[([^\]]+)\]\(([^)]+)\)', sources_content)
            if len(markdown_links) == 0:
                return False, "Sources section must contain markdown links"

        return True, None

    @staticmethod
    def validate_mode_requirements(
        mode_config: ChatModeConfig,
        content: str,
        tool_calls: list[dict] | None = None
    ) -> tuple[bool, Optional[str]]:
        """Validate all mode-specific requirements."""
        if mode_config.require_sources:
            return ModeValidator.validate_research_sources(content)
        return True, None
```

**Integration in streaming:**

Update `/Users/sean/Coding/sideBar/backend/api/services/claude_streaming.py`:

```python
# Before yielding complete event:
if mode_config.require_sources or mode_config.require_writing_draft:
    from api.services.mode_validators import ModeValidator

    full_content = ""  # Collect all assistant text
    for msg in messages:
        if msg.get("role") == "assistant":
            for block in msg.get("content", []):
                if block.get("type") == "text":
                    full_content += block.get("text", "")

    is_valid, error_msg = ModeValidator.validate_mode_requirements(
        mode_config,
        full_content,
        tool_uses
    )

    if not is_valid:
        logger.warning(f"Mode validation failed: {error_msg}")
        yield {
            "type": "mode_validation_warning",
            "data": {"mode": mode_config.id.value, "message": error_msg}
        }
```

### 4.2 Writing Mode: Draft Note Workflow

**File: `/Users/sean/Coding/sideBar/backend/api/services/writing_mode_helper.py` (NEW)**

```python
class WritingModeHelper:
    @staticmethod
    def get_or_create_draft_note(
        db: Session,
        user_id: str,
        conversation_id: uuid.UUID,
        conversation_title: str | None = None
    ) -> dict:
        """Get or create writing draft note for conversation."""
        conversation = ConversationService.get_conversation(db, user_id, conversation_id)

        # Check if draft note already exists
        if conversation.writing_draft_note_id:
            note = NoteService.get_note(db, user_id, conversation.writing_draft_note_id)
            if note:
                return {
                    "id": str(note.id),
                    "title": note.title,
                    "content": note.content or ""
                }

        # Create new draft note
        title = f"Writing Draft - {conversation_title or 'Untitled'}"
        note = NoteService.create_note(
            db,
            user_id,
            title=title,
            content="# Writing Draft\n\n",
            folder=None
        )

        # Link to conversation
        conversation.writing_draft_note_id = note.id
        db.commit()

        return {"id": str(note.id), "title": note.title, "content": note.content or ""}

    @staticmethod
    def update_draft_note(
        db: Session,
        user_id: str,
        note_id: uuid.UUID,
        content: str
    ) -> dict:
        """Update writing draft note content."""
        note = NoteService.update_note(db, user_id, note_id, content=content)
        return {"id": str(note.id), "title": note.title, "content": note.content or ""}
```

**Update tool context:**

Modify `/Users/sean/Coding/sideBar/backend/api/schemas/tool_context.py`:
```python
@dataclass
class ToolExecutionContext:
    # ... existing fields
    conversation_title: str | None = None
    mode: str | None = None
```

### Deliverables
- ✅ Research mode sources validator
- ✅ Writing mode draft note helpers
- ✅ Validation integrated into streaming
- ✅ Warning events for validation failures

---

## Phase 5: Self-Switching Skill (2 days)

### Objectives
- Create mode switch skill
- Register tool definition
- Handle mode switch events in streaming
- Update mode_config mid-conversation

### 5.1 Create Skill Script

**File: `/Users/sean/Coding/sideBar/backend/skills/chat-mode/scripts/switch_mode.py` (NEW)**

```python
#!/usr/bin/env python3
"""Switch chat mode mid-conversation."""
import sys
import json
import argparse

VALID_MODES = ["quick", "research", "planning", "brainstorming", "writing"]

def main():
    parser = argparse.ArgumentParser(description="Switch chat mode")
    parser.add_argument("--mode", required=True, choices=VALID_MODES)
    parser.add_argument("--reason", help="Reason for switching")
    parser.add_argument("--json", action="store_true")

    args = parser.parse_args()

    result = {
        "success": True,
        "data": {
            "mode": args.mode,
            "reason": args.reason or f"Switched to {args.mode} mode"
        }
    }

    if args.json:
        print(json.dumps(result))
    else:
        print(f"Switched to {args.mode} mode")

    return 0

if __name__ == "__main__":
    sys.exit(main())
```

**File: `/Users/sean/Coding/sideBar/backend/skills/chat-mode/SKILL.md` (NEW)**

```markdown
---
id: chat-mode
name: Chat Mode Management
description: Switch between chat modes
version: 1.0.0
---

# Chat Mode Management

Switch between Quick, Research, Planning, Brainstorming, and Writing modes.
```

### 5.2 Register Tool Definition

**File: `/Users/sean/Coding/sideBar/backend/api/services/tools/definitions_misc.py`**

Add to tool definitions:
```python
"Switch Chat Mode": {
    "skill": "chat-mode",
    "script": "switch_mode.py",
    "description": "Switch to a different chat mode based on user intent",
    "input_schema": {
        "type": "object",
        "properties": {
            "mode": {
                "type": "string",
                "enum": ["quick", "research", "planning", "brainstorming", "writing"],
                "description": "Target chat mode"
            },
            "reason": {
                "type": "string",
                "description": "Why you are switching modes (shown to user)"
            }
        },
        "required": ["mode", "reason"]
    },
    "build_args": lambda params: [
        "--mode", params["mode"],
        "--reason", params.get("reason", ""),
        "--json"
    ]
}
```

### 5.3 Handle Mode Switch Events

**File: `/Users/sean/Coding/sideBar/backend/api/services/claude_streaming.py`**

In tool result handling:
```python
elif display_name == "Switch Chat Mode":
    # Emit mode switch event
    yield {
        "type": "mode_switch",
        "data": {
            "mode": result_data.get("mode"),
            "reason": result_data.get("reason")
        }
    }

    # Update mode_config for subsequent rounds
    try:
        new_mode = ChatModeType(result_data.get("mode"))
        mode_config = get_mode_config(new_mode)
        logger.info(f"Mode switched to {new_mode.value}")
    except ValueError:
        logger.warning(f"Invalid mode: {result_data.get('mode')}")
```

### Deliverables
- ✅ Switch mode skill script
- ✅ Tool definition registered
- ✅ Mode switch events emitted
- ✅ Mode config updates mid-conversation

---

## Phase 6: Frontend UI Components (3-4 days)

### Objectives
- Create mode selector component
- Update ChatInput with mode icons
- Add keyboard shortcuts (⌘+Q/R/P/B/W)
- Handle mode changes in chat store
- Reflect assistant-initiated mode switches

### 6.1 Mode Selector Component

**File: `/Users/sean/Coding/sideBar/frontend/src/lib/components/chat/ModeSelector.svelte` (NEW)**

```svelte
<script lang="ts">
  import { Button } from '$lib/components/ui/button';
  import { CHAT_MODES, type ChatModeType } from '$lib/types/chatMode';
  import * as Icons from 'lucide-svelte';

  export let selectedMode: ChatModeType = 'quick';
  export let disabled = false;
  export let onModeSelect: ((mode: ChatModeType) => void) | undefined = undefined;

  function getIcon(iconName: string) {
    const iconMap: Record<string, any> = {
      'zap': Icons.Zap,
      'search': Icons.Search,
      'list-checks': Icons.ListChecks,
      'lightbulb': Icons.Lightbulb,
      'pen-tool': Icons.PenTool
    };
    return iconMap[iconName] || Icons.MessageSquare;
  }

  const modes: ChatModeType[] = ['quick', 'research', 'planning', 'brainstorming', 'writing'];
</script>

<div class="mode-selector">
  {#each modes as mode}
    {@const config = CHAT_MODES[mode]}
    {@const IconComponent = getIcon(config.icon)}
    <Button
      size="icon"
      variant={selectedMode === mode ? 'default' : 'ghost'}
      class="mode-button"
      onclick={() => onModeSelect?.(mode)}
      aria-label={config.displayName}
      title={`${config.displayName} (${config.keyboardShortcut})\n${config.description}`}
      {disabled}
    >
      <svelte:component this={IconComponent} size={16} />
    </Button>
  {/each}
</div>

<style>
  .mode-selector {
    display: inline-flex;
    gap: 0.25rem;
    align-items: center;
  }

  :global(.mode-button) {
    transition: all 0.2s ease;
  }
</style>
```

### 6.2 Update ChatInput

**File: `/Users/sean/Coding/sideBar/frontend/src/lib/components/chat/ChatInput.svelte`**

Add mode selector and keyboard shortcuts:
```svelte
<script lang="ts">
  import ModeSelector from './ModeSelector.svelte';
  import type { ChatModeType } from '$lib/types/chatMode';

  export let selectedMode: ChatModeType = 'quick';
  export let onModeChange: ((mode: ChatModeType) => void) | undefined = undefined;

  function handleKeydown(event: KeyboardEvent) {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      handleSubmit();
      return;
    }

    // Mode shortcuts: ⌘+Q/R/P/B/W
    if (event.metaKey || event.ctrlKey) {
      const keyModeMap: Record<string, ChatModeType> = {
        'q': 'quick',
        'r': 'research',
        'p': 'planning',
        'b': 'brainstorming',
        'w': 'writing'
      };

      const mode = keyModeMap[event.key.toLowerCase()];
      if (mode) {
        event.preventDefault();
        onModeChange?.(mode);
      }
    }
  }
</script>

<div class="chat-input-bar">
  <div class="chat-input-shell">
    <textarea
      bind:this={textarea}
      bind:value={inputValue}
      onkeydown={handleKeydown}
      oninput={resizeTextarea}
      placeholder="Ask Anything..."
      {disabled}
    ></textarea>
    <div class="chat-input-actions">
      <!-- Left: Attachment button -->
      <div class="chat-input-left">
        <Button size="icon" variant="ghost" onclick={handleAttachClick}>
          <Paperclip size={16} />
        </Button>
      </div>

      <!-- Center: Mode selector -->
      <div class="chat-input-center">
        <ModeSelector {selectedMode} {disabled} onModeSelect={onModeChange} />
      </div>

      <!-- Right: Send button -->
      <Button onclick={handleSubmit} disabled={disabled || !inputValue.trim()} size="icon">
        <Send size={16} />
      </Button>
    </div>
  </div>
</div>
```

### 6.3 Update Chat Store

**File: `/Users/sean/Coding/sideBar/frontend/src/lib/stores/chat.ts`**

```typescript
export interface ChatState {
  // ... existing fields
  selectedMode: ChatModeType;  // NEW
}

function createChatStore() {
  const { subscribe, set, update } = writable<ChatState>({
    // ... existing state
    selectedMode: 'quick'
  });

  return {
    subscribe,

    setMode(mode: ChatModeType) {
      update(state => ({ ...state, selectedMode: mode }));
    },

    handleModeSwitch(mode: ChatModeType, reason?: string) {
      update(state => ({ ...state, selectedMode: mode }));
      if (reason) {
        toast.info(`Switched to ${CHAT_MODES[mode].displayName} mode: ${reason}`);
      }
    },

    async sendMessage(content: string, mode: ChatModeType) {
      // ... existing logic

      const userMessage: Message = {
        // ... existing fields
        mode  // NEW: attach mode to message
      };

      const assistantMessage: Message = {
        // ... existing fields
        mode  // NEW: attach mode to message
      };

      // ... persist and return
    }
  };
}
```

### 6.4 Update ChatWindow

**File: `/Users/sean/Coding/sideBar/frontend/src/lib/components/chat/ChatWindow.svelte`**

```svelte
<script lang="ts">
  import type { ChatModeType } from '$lib/types/chatMode';

  $: selectedMode = $chatStore.selectedMode;

  function handleModeChange(mode: ChatModeType) {
    chatStore.setMode(mode);
  }

  async function handleSend(message: string) {
    const { assistantMessageId, userMessageId } = await chatStore.sendMessage(
      message,
      selectedMode  // NEW
    );

    await chatSse.connect({
      assistantMessageId,
      message,
      conversationId: conversationId ?? undefined,
      userMessageId,
      openContext,
      attachments: attachmentsForMessage,
      currentLocation,
      currentLocationLevels,
      currentWeather,
      currentTimezone,
      mode: selectedMode  // NEW
    });
  }
</script>

<ChatInput
  onsend={handleSend}
  onattach={handleAttach}
  onremoveattachment={handleRemoveReadyAttachment}
  readyattachments={readyAttachments}
  disabled={isSendDisabled}
  selectedMode={selectedMode}
  onModeChange={handleModeChange}
/>
```

### 6.5 Update SSE Client

**File: `/Users/sean/Coding/sideBar/frontend/src/lib/api/sse.ts`**

```typescript
export interface SSECallbacks {
  // ... existing callbacks
  onModeSwitch?: (data: { mode: ChatModeType; reason?: string }) => void;
}

// In handleEvent:
case 'mode_switch':
  callbacks.onModeSwitch?.(data);
  break;
```

**File: `/Users/sean/Coding/sideBar/frontend/src/lib/composables/useChatSSE.ts`**

```typescript
onModeSwitch: (data) => {
  chatStore.handleModeSwitch(data.mode as ChatModeType, data.reason);
}
```

### 6.6 Message Mode Badge (Optional)

**File: `/Users/sean/Coding/sideBar/frontend/src/lib/components/chat/Message.svelte`**

```svelte
<script lang="ts">
  import { CHAT_MODES } from '$lib/types/chatMode';
  export let message: Message;

  $: modeConfig = message.mode ? CHAT_MODES[message.mode as ChatModeType] : null;
</script>

<div class="message-bubble">
  <div class="message-header">
    <span class="message-role">{message.role}</span>
    {#if modeConfig}
      <span class="message-mode-badge" title={modeConfig.description}>
        {modeConfig.displayName}
      </span>
    {/if}
  </div>
  <!-- ... content ... -->
</div>

<style>
  .message-mode-badge {
    padding: 0.125rem 0.375rem;
    border-radius: 0.25rem;
    background: var(--color-muted);
    font-size: 0.7rem;
    text-transform: uppercase;
  }
</style>
```

### Deliverables
- ✅ ModeSelector component with icons
- ✅ Keyboard shortcuts (⌘+Q/R/P/B/W)
- ✅ Chat store mode management
- ✅ ChatWindow integration
- ✅ SSE mode_switch event handling
- ✅ Message mode badges (optional)

---

## Phase 7: Testing & Validation (2-3 days)

### 7.1 Backend Unit Tests

**File: `/Users/sean/Coding/sideBar/backend/tests/api/test_chat_modes.py` (NEW)**

```python
def test_mode_configs_exist():
    """All modes should have valid configurations."""
    for mode in ChatModeType:
        config = get_mode_config(mode)
        assert config.id == mode
        assert config.model

def test_research_sources_validation():
    """Research mode should validate sources section."""
    valid = "Research\n\nSources:\n- [A](https://example.com)"
    is_valid, _ = ModeValidator.validate_research_sources(valid)
    assert is_valid

def test_quick_mode_uses_haiku():
    config = get_mode_config(ChatModeType.QUICK)
    assert "haiku" in config.model.lower()
    assert config.max_tool_rounds <= 3
```

### 7.2 Frontend Tests

**File: `/Users/sean/Coding/sideBar/frontend/src/lib/components/chat/ModeSelector.test.ts` (NEW)**

```typescript
describe('ModeSelector', () => {
  it('renders all mode buttons', () => {
    const { container } = render(ModeSelector);
    expect(container.querySelectorAll('.mode-button').length).toBe(5);
  });

  it('highlights selected mode', () => {
    const { container } = render(ModeSelector, { props: { selectedMode: 'research' }});
    const btn = container.querySelector('[aria-label="Research"]');
    expect(btn).toHaveAttribute('data-state', 'on');
  });

  it('calls onModeSelect on click', async () => {
    const onModeSelect = vi.fn();
    const { container } = render(ModeSelector, { props: { onModeSelect }});
    await fireEvent.click(container.querySelector('[aria-label="Planning"]')!);
    expect(onModeSelect).toHaveBeenCalledWith('planning');
  });
});
```

### 7.3 Integration Test Scenarios

1. **Quick mode:** Send message → verify Haiku model used, max 3 tool rounds
2. **Research mode:** Send message with web search → verify sources validation
3. **Writing mode:** Send message → verify draft note created/updated
4. **Self-switch:** Use Switch Chat Mode tool → verify UI updates, mode changes
5. **Keyboard shortcuts:** Press ⌘+R → verify Research mode selected
6. **Persistence:** Reload conversation → verify messages show correct mode badges
7. **Backward compatibility:** Load old conversation → verify defaults to Quick mode

### Deliverables
- ✅ Backend unit tests for modes and validation
- ✅ Frontend component tests
- ✅ Integration test scenarios documented
- ✅ Manual testing checklist

---

## Phase 8: Documentation & Rollout (1 day)

### 8.1 User Documentation

**File: `/Users/sean/Coding/sideBar/docs/CHAT_MODES.md` (NEW)**

Document:
- What chat modes are and when to use each
- How modes affect behavior (model, tools, validation)
- Keyboard shortcuts reference
- How assistant auto-switching works
- Writing mode draft note workflow
- Research mode sources requirements

### 8.2 Migration Execution

```bash
# Run migrations
cd backend
alembic upgrade head

# Verify backfill
psql $DATABASE_URL -c "
  SELECT id, msg->>'mode' as mode
  FROM conversations, jsonb_array_elements(messages) AS msg
  LIMIT 10;
"
```

### 8.3 Environment Configuration

Update `.env.example`:
```bash
# Chat modes (optional overrides)
ENABLE_CHAT_MODES=true
DEFAULT_CHAT_MODE=quick
```

### Deliverables
- ✅ User-facing documentation
- ✅ Migrations executed and verified
- ✅ Environment variables documented
- ✅ Rollout checklist completed

---

## Risk Mitigation & Edge Cases

| Risk | Mitigation |
|------|------------|
| Mode drift during tool loops | Pass mode_config through entire streaming pipeline, update when switch tool called |
| Backward compatibility | Default old messages to "quick" in migration, handle missing mode gracefully |
| Mode switch mid-typing | Mode selector always enabled, applies to next message sent |
| Sources validation false positives | Only validate if web_search used, allow graceful degradation with warnings |
| Writing draft note conflicts | One draft per conversation (FK), update existing instead of creating duplicates |
| Performance impact | Validation only for modes requiring it, efficient regex patterns |
| Model cost | Quick mode uses Haiku to reduce costs, user can always override |

---

## Effort Estimates

| Phase | Effort | Complexity |
|-------|--------|------------|
| 1. Foundation | 2-3 days | Low-Medium |
| 2. Database | 1-2 days | Low |
| 3. Backend Integration | 3-4 days | Medium |
| 4. Validation | 2-3 days | Medium |
| 5. Self-Switching | 2 days | Low-Medium |
| 6. Frontend UI | 3-4 days | Medium |
| 7. Testing | 2-3 days | Medium |
| 8. Documentation | 1 day | Low |
| **Total** | **17-25 days** | |

---

## Critical Files Summary

### Backend (Create)
- `/Users/sean/Coding/sideBar/backend/api/schemas/chat_mode.py` - Mode types and schemas
- `/Users/sean/Coding/sideBar/backend/api/config/chat_modes.py` - Mode configurations
- `/Users/sean/Coding/sideBar/backend/api/services/mode_validators.py` - Validation logic
- `/Users/sean/Coding/sideBar/backend/api/services/writing_mode_helper.py` - Writing helpers
- `/Users/sean/Coding/sideBar/backend/skills/chat-mode/scripts/switch_mode.py` - Switch skill
- `/Users/sean/Coding/sideBar/backend/api/alembic/versions/20260107_1400-028_add_message_mode.py` - Migration
- `/Users/sean/Coding/sideBar/backend/api/alembic/versions/20260107_1430-029_add_writing_draft_note.py` - Migration

### Backend (Modify)
- `/Users/sean/Coding/sideBar/backend/api/routers/chat.py` - Accept mode parameter
- `/Users/sean/Coding/sideBar/backend/api/services/prompt_context_service.py` - Inject mode
- `/Users/sean/Coding/sideBar/backend/api/services/claude_client.py` - Use mode config
- `/Users/sean/Coding/sideBar/backend/api/services/claude_streaming.py` - Enforce mode limits
- `/Users/sean/Coding/sideBar/backend/api/services/tools/definitions_misc.py` - Register switch tool
- `/Users/sean/Coding/sideBar/backend/api/models/conversation.py` - Add writing_draft_note_id
- `/Users/sean/Coding/sideBar/backend/api/schemas/tool_context.py` - Add mode fields

### Frontend (Create)
- `/Users/sean/Coding/sideBar/frontend/src/lib/types/chatMode.ts` - Mode types
- `/Users/sean/Coding/sideBar/frontend/src/lib/components/chat/ModeSelector.svelte` - Mode selector UI

### Frontend (Modify)
- `/Users/sean/Coding/sideBar/frontend/src/lib/types/chat.ts` - Add mode to Message
- `/Users/sean/Coding/sideBar/frontend/src/lib/components/chat/ChatInput.svelte` - Mode selector + shortcuts
- `/Users/sean/Coding/sideBar/frontend/src/lib/components/chat/ChatWindow.svelte` - Wire mode
- `/Users/sean/Coding/sideBar/frontend/src/lib/stores/chat.ts` - Mode state management
- `/Users/sean/Coding/sideBar/frontend/src/lib/api/sse.ts` - Handle mode_switch events
- `/Users/sean/Coding/sideBar/frontend/src/lib/composables/useChatSSE.ts` - Mode switch callback

---

## Success Criteria

**Phase 1-2 Complete:**
- ✅ Mode types defined and configured
- ✅ Database migrations executed
- ✅ Existing messages backfilled

**Phase 3-4 Complete:**
- ✅ Backend accepts and uses mode parameter
- ✅ Mode controls model, params, tool limits
- ✅ Research mode validates sources
- ✅ Writing mode creates draft notes

**Phase 5-6 Complete:**
- ✅ Switch Chat Mode tool works
- ✅ UI shows mode icons and keyboard shortcuts
- ✅ Assistant can switch modes with notification
- ✅ Messages persist with mode metadata

**Phase 7-8 Complete:**
- ✅ All tests passing
- ✅ Documentation complete
- ✅ Ready for production rollout

---

## Next Steps

1. ✅ Review and approve this plan
2. ⏭️ Begin Phase 1: Foundation (2-3 days)
3. ⏭️ Execute database migrations in Phase 2 (1-2 days)
4. ⏭️ Implement backend orchestration in Phase 3 (3-4 days)
5. ⏭️ Build validation and enforcement in Phase 4 (2-3 days)
6. ⏭️ Create self-switching skill in Phase 5 (2 days)
7. ⏭️ Build frontend UI in Phase 6 (3-4 days)
8. ⏭️ Test thoroughly in Phase 7 (2-3 days)
9. ⏭️ Document and roll out in Phase 8 (1 day)
