# Claude Memory Tool Implementation Plan

## Overview

Implement Claude's official memory tool (beta feature `memory_20250818`) to enable persistent, global memory across all conversations in sideBar. Memory will help Claude understand the user better by remembering facts, relationships, project context, and learnings.

## Requirements Summary

- **Approach**: Full Claude memory tool implementation (official spec)
- **Scope**: Global user memory across all conversations
- **UI**: Tool indicators in chat + dedicated settings pane for management
- **Content**: User understanding (facts, relationships, projects, learnings) - NOT settings/preferences
- **Storage**: PostgreSQL with user isolation
- **Beta**: `context-management-2025-06-27` header required

## Implementation Architecture

### 1. Database Layer

**New Table**: `user_memories`
- Columns: `id`, `user_id`, `path`, `content`, `created_at`, `updated_at`
- Unique constraint: `(user_id, path)`
- Index: `(user_id, path)` for fast lookups
- Virtual paths: `/memories/filename.md` (markdown only)

**Migration**: Create Alembic migration to add table with GIN indexes

### 2. Backend Core

**Memory Tool Handler** (NEW: `/backend/api/services/memory_tool_handler.py`)
- Implements all Claude memory commands: `view`, `create`, `str_replace`, `insert`, `delete`, `rename`
- Path validation: Must start with `/memories/`, no traversal, `.md` extension only
- Security: User isolation, size limits (100KB per file), SQL injection protection
- Returns normalized results matching tool execution pattern

**Tool Integration** (`/backend/api/services/tool_mapper.py`)
- Add "Memory Tool" to tools dict (after line 865)
- Add "memory" to `EXPOSED_SKILLS` set
- Add special case handler in `execute_tool()` method (after line 1009, similar to "Generate Prompts")
- Route to `MemoryToolHandler.execute_command()`

**Claude Client** (`/backend/api/services/claude_client.py`)
- Add beta header to `stream_args` (line ~161): `"betas": ["context-management-2025-06-27"]`
- Add memory SSE events after tool execution (emit `memory_created`, `memory_updated`, `memory_deleted`)

**Prompt Context Service** (`/backend/api/services/prompt_context_service.py`)
- Add memory retrieval in `build_prompts()` method (line ~73)
- Call `MemoryToolHandler.get_all_memories_for_prompt(db, user_id)`
- Insert memory block into system prompt before `open_block`
- Format: Markdown header + all memory file contents

**Management API** (NEW: `/backend/api/routers/memories.py`)
- REST endpoints: `GET /api/memories`, `GET /api/memories/{id}`, `POST /api/memories`, `PATCH /api/memories/{id}`, `DELETE /api/memories/{id}`
- Pydantic models: `MemoryResponse`, `MemoryCreate`, `MemoryUpdate`
- Authentication via bearer token
- Register in `/backend/api/main.py`

### 3. Frontend Implementation

**Types** (NEW: `/frontend/src/lib/types/memory.ts`)
- `Memory`, `MemoryCreate`, `MemoryUpdate` interfaces

**API Service** (NEW: `/frontend/src/lib/services/memories.ts`)
- Methods: `list()`, `get(id)`, `create()`, `update()`, `delete()`
- Standard fetch API pattern

**Store** (NEW: `/frontend/src/lib/stores/memories.ts`)
- Writable store with `memories`, `isLoading`, `error` state
- Methods: `load()`, `create()`, `update()`, `delete()`
- Auto-sorting by path

**Settings UI** (NEW: `/frontend/src/lib/components/settings/MemorySettings.svelte`)
- List all memories with path, timestamp, content preview
- Create new memory form (path + content textarea)
- Edit/delete actions per memory
- Markdown content display
- Empty state with helpful message

**SSE Integration** (`/frontend/src/lib/api/sse.ts`)
- Add callbacks: `onMemoryCreated`, `onMemoryUpdated`, `onMemoryDeleted`
- Handle events in switch statement (line ~195)
- Optional: Refresh memory store or show toast

**Chat Integration** (`/frontend/src/lib/components/chat/ChatWindow.svelte`)
- Wire up memory event callbacks
- Tool indicators will show memory operations automatically via existing pattern

## Critical Files

### Files to Create
1. `/backend/api/services/memory_tool_handler.py` - Core memory tool implementation (~400 lines)
2. `/backend/api/models/user_memory.py` - SQLAlchemy model (~25 lines)
3. `/backend/api/alembic/versions/YYYYMMDD_HHMM-NNN_add_user_memories_table.py` - Migration
4. `/backend/api/routers/memories.py` - REST API (~150 lines)
5. `/frontend/src/lib/types/memory.ts` - TypeScript types (~15 lines)
6. `/frontend/src/lib/services/memories.ts` - API client (~50 lines)
7. `/frontend/src/lib/stores/memories.ts` - State management (~60 lines)
8. `/frontend/src/lib/components/settings/MemorySettings.svelte` - UI (~200 lines)

### Files to Modify
1. `/backend/api/services/tool_mapper.py` - Add memory tool definition and handler
2. `/backend/api/services/claude_client.py` - Add beta header and memory events
3. `/backend/api/services/prompt_context_service.py` - Inject memories into prompts
4. `/backend/api/main.py` - Register memories router
5. `/frontend/src/lib/api/sse.ts` - Add memory event callbacks
6. `/frontend/src/lib/components/chat/ChatWindow.svelte` - Wire up memory events
7. `/frontend/src/routes/settings/+page.svelte` - Add memory settings tab/section

## Implementation Phases

### Phase 1: Backend Core (Priority: Critical)
1. Create `UserMemory` model and migration
2. Implement `MemoryToolHandler` with all 6 commands
3. Add to `ToolMapper` as special case handler
4. Update `ClaudeClient` with beta header
5. Test memory operations via direct tool execution

**Validation**: Memory tool callable via ToolMapper, all commands work, path validation enforced

### Phase 2: Prompt Integration (Priority: Critical)
1. Add memory retrieval to `PromptContextService.build_prompts()`
2. Test memory injection into system prompts
3. Verify memories persist across conversations
4. Add SSE events for memory operations in `ClaudeClient`

**Validation**: Memories appear in prompts, Claude can access them, tool events stream to frontend

### Phase 3: Management API (Priority: High)
1. Create `/api/memories` router with CRUD endpoints
2. Test authentication and user isolation
3. Register router in main app

**Validation**: REST API functional, proper authorization, no cross-user access

### Phase 4: Frontend UI (Priority: High)
1. Create memory types and API service
2. Implement memory store
3. Build `MemorySettings.svelte` component
4. Integrate into settings page
5. Wire up SSE event handlers in chat

**Validation**: UI displays memories, create/edit/delete works, auto-refresh on tool use

### Phase 5: Polish (Priority: Medium)
1. Add toast notifications for memory operations
2. Improve error messages and validation
3. Add usage documentation
4. Performance optimization (query caching if needed)

## Security Considerations

**Path Validation**
- All paths must start with `/memories/`
- Block path traversal (`..`, `//`)
- Enforce `.md` extension
- Max path length: 500 chars
- Regex: `^/memories/[a-zA-Z0-9_/-]+\.md$`

**User Isolation**
- All DB queries filter by `user_id`
- Unique constraint prevents path conflicts
- No cross-user memory access possible

**Content Limits**
- Max 100KB per memory file
- Reject oversized content before DB write

**Audit Logging**
- All memory operations logged via `AuditLogger`
- Include: user_id, command, path, success/failure, duration

## Memory Tool Commands Specification

Following Claude's official spec:

1. **view** - List directory or view file contents
   - List: `{"command": "view"}` returns all memories
   - File: `{"command": "view", "path": "/memories/work.md"}` returns content

2. **create** - Create new memory file
   - `{"command": "create", "path": "/memories/project.md", "content": "..."}`
   - Error if file exists

3. **str_replace** - Replace text in file
   - `{"command": "str_replace", "path": "...", "old_str": "...", "new_str": "..."}`
   - Error if string not found or duplicate

4. **insert** - Insert at start/end
   - `{"command": "insert", "path": "...", "position": "start|end", "content": "..."}`

5. **delete** - Delete file
   - `{"command": "delete", "path": "/memories/old.md"}`

6. **rename** - Rename/move file
   - `{"command": "rename", "old_path": "...", "new_path": "..."}`
   - Error if destination exists

## Testing Strategy

**Unit Tests**
- `test_memory_tool_handler.py`: All 6 commands, path validation, error cases
- `test_memory_model.py`: Model constraints, unique violations

**Integration Tests**
- Memory tool execution via ToolMapper
- Memory injection into prompts
- SSE event delivery
- API endpoint authorization

**E2E Tests**
- Create memory via chat conversation
- Edit memory in settings UI
- Verify memory persists across conversations
- Delete memory and verify removal from prompts

## Rollback Plan

- Database migration can be rolled back: `alembic downgrade -1`
- Feature can be disabled by removing memory tool from ToolMapper
- Optional: Add feature flag `settings.memory_enabled` for gradual rollout

## Success Criteria

✅ Claude can create/update/delete memories during conversations
✅ Memories persist globally across all conversations
✅ Memory content appears in system prompts automatically
✅ Users can browse/edit/delete memories in settings UI
✅ Tool indicators show memory operations in chat
✅ All memory operations are user-isolated and secure
✅ No performance degradation on prompt assembly
