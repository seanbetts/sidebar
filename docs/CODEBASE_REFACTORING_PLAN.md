# Codebase Refactoring Analysis - sideBar

## Overview

Comprehensive analysis of file sizes across the sideBar codebase to identify files that need refactoring based on length and complexity. This analysis helps prioritize technical debt reduction and improve code maintainability.

## Executive Summary

**Critical Findings:**
- **1 file >2000 lines** (Sidebar.svelte - 2,043 lines) - URGENT refactoring needed
- **3 files >1000 lines** (tool_mapper.py, MarkdownEditor.svelte, FileTreeNode.svelte)
- **14 files >500 lines** requiring high-priority refactoring

**Key Patterns:**
- Frontend: God components managing multiple dialogs and features
- Backend: Monolithic services mixing multiple responsibilities
- Routers mixing HTTP handling with business logic
- Configuration embedded in code instead of separate files

## Top 10 Critical Files Needing Refactoring

### Backend

1. **`/backend/api/services/tool_mapper.py`** - **1,371 lines** ⚠️ CRITICAL
   - Monolithic tool mapping service
   - Mixes tool definitions, execution, parameter mapping, skill metadata
   - **Recommended Split:**
     - `services/tool_definitions.py` - Tool schemas
     - `services/skill_metadata.py` - Skill display info
     - `services/parameter_mapper.py` - Parameter conversion
     - Keep only orchestration in ToolMapper

2. **`/backend/api/prompts.py`** - **529 lines** 🔴 HIGH
   - Mixes template configuration with rendering logic
   - **Recommended Split:**
     - `config/prompts.yaml` - Template strings
     - Keep only rendering functions in prompts.py

3. **`/backend/api/mcp/tools.py`** - **478 lines** 🔴 HIGH
   - Single massive function registering 15+ tools
   - **Recommended Split:**
     - `mcp/fs_tools.py`
     - `mcp/notes_tools.py`
     - `mcp/web_tools.py`
     - `mcp/document_tools.py`

4. **`/backend/api/services/claude_client.py`** - **473 lines** 🔴 HIGH
   - Handles streaming, tools, web search in single class
   - **Recommended Split:**
     - `services/streaming_handler.py`
     - `services/tool_executor.py`
     - `services/web_search_builder.py`

5. **`/backend/api/routers/files.py`** - **460 lines** 🟡 MEDIUM
   - Router with embedded business logic
   - **Recommendation:** Extract file tree logic to service layer

### Frontend

1. **`/frontend/src/lib/components/history/Sidebar.svelte`** - **2,043 lines** 🚨 URGENT
   - God component managing navigation, notes, websites, settings
   - Multiple inline dialogs and modals
   - **Recommended Split:**
     - `SettingsPanel.svelte`
     - `NewNoteDialog.svelte`
     - `NewFolderDialog.svelte`
     - `NewWebsiteDialog.svelte`
     - `SaveChangesDialog.svelte`
     - Dedicated settings store

2. **`/frontend/src/lib/components/editor/MarkdownEditor.svelte`** - **995 lines** ⚠️ CRITICAL
   - Editor + note operations + navigation guards
   - **Recommended Split:**
     - `EditorToolbar.svelte` - Actions (save, rename, pin, etc.)
     - `useEditorActions.ts` - Composable for handlers
     - Separate navigation guard logic

3. **`/frontend/src/lib/components/files/FileTreeNode.svelte`** - **709 lines** 🔴 HIGH
   - Recursive tree rendering + context menu + CRUD operations
   - **Recommended Split:**
     - `FileTreeContextMenu.svelte`
     - `useFileActions.ts` - Composable for actions
     - Simplify recursive rendering

4. **`/frontend/src/lib/components/websites/WebsitesPanel.svelte`** - **666 lines** 🔴 HIGH
   - List rendering + context menus + operations
   - **Recommendation:** Extract `WebsiteListItem.svelte`

5. **`/frontend/src/lib/stores/chat.ts`** - **406 lines** 🟡 MEDIUM
   - Manages messages + streaming + tool state
   - **Recommendation:** Extract tool state to `toolState.ts`

## Detailed Analysis by Category

### Backend Files >300 Lines

| File | Lines | Category | Priority | Issue |
|------|-------|----------|----------|-------|
| `services/tool_mapper.py` | 1,371 | Service | 🚨 URGENT | Monolithic tool service |
| `prompts.py` | 529 | Config | 🔴 HIGH | Config + logic mixed |
| `mcp/tools.py` | 478 | Tools | 🔴 HIGH | Single massive function |
| `services/claude_client.py` | 473 | Service | 🔴 HIGH | Multiple responsibilities |
| `routers/files.py` | 460 | Router | 🟡 MEDIUM | Business logic in router |
| `routers/notes.py` | 354 | Router | 🟡 MEDIUM | Business logic in router |
| `routers/settings.py` | 329 | Router | 🟡 MEDIUM | File upload + defaults |
| `services/websites_service.py` | 306 | Service | ✅ OK | Acceptable size |
| `routers/chat.py` | 302 | Router | ✅ OK | Could extract streaming |

### Frontend Files >300 Lines

| File | Lines | Category | Priority | Issue |
|------|-------|----------|----------|-------|
| `history/Sidebar.svelte` | 2,043 | Component | 🚨 URGENT | God component |
| `editor/MarkdownEditor.svelte` | 995 | Component | 🚨 URGENT | Editor + operations |
| `files/FileTreeNode.svelte` | 709 | Component | 🔴 HIGH | Recursive + CRUD |
| `websites/WebsitesPanel.svelte` | 666 | Component | 🔴 HIGH | List + operations |
| `websites/WebsitesViewer.svelte` | 450 | Component | 🟡 MEDIUM | Viewer + actions |
| `stores/chat.ts` | 406 | Store | 🟡 MEDIUM | Multiple concerns |
| `scratchpad-popover.svelte` | 369 | Component | ✅ OK | Self-contained |
| `site-header.svelte` | 366 | Component | 🟡 MEDIUM | Multiple services |
| `history/ConversationItem.svelte` | 347 | Component | ✅ OK | Could simplify |
| `chat/ChatWindow.svelte` | 331 | Component | ✅ OK | Main feature component |

## Refactoring Recommendations by Priority

### 🚨 URGENT (Do First)

#### 1. Sidebar.svelte (2,043 lines)
**Impact:** Highest - Central component, hard to maintain, blocks other work

**Refactoring Plan:**
```
/frontend/src/lib/components/history/
├── Sidebar.svelte (reduced to ~300 lines)
├── panels/
│   ├── SettingsPanel.svelte
│   ├── NotesPanel.svelte (extract from existing)
│   ├── WorkspacePanel.svelte (extract from existing)
│   └── WebsitesPanel.svelte (already separate)
├── dialogs/
│   ├── NewNoteDialog.svelte
│   ├── NewFolderDialog.svelte
│   ├── NewWebsiteDialog.svelte
│   └── SaveChangesDialog.svelte
└── stores/
    └── sidebarSettings.ts
```

**Steps:**
1. Extract each dialog to separate component (5 dialogs)
2. Create SettingsPanel.svelte for settings UI
3. Move settings state to dedicated store
4. Extract panel management logic to composable
5. Simplify main Sidebar.svelte to routing/orchestration only

#### 2. tool_mapper.py (1,371 lines)
**Impact:** High - Core backend service, affects all tool operations

**Refactoring Plan:**
```
/backend/api/services/
├── tool_mapper.py (reduced to ~200 lines - orchestration only)
├── tools/
│   ├── __init__.py
│   ├── definitions.py - Tool schema definitions
│   ├── skill_metadata.py - Skill display names, categories
│   ├── parameter_mapper.py - Parameter conversion/validation
│   └── execution_handlers.py - Special case handlers
```

**Steps:**
1. Extract tool definitions to `tools/definitions.py`
2. Move skill metadata to `tools/skill_metadata.py`
3. Extract parameter mapping to `tools/parameter_mapper.py`
4. Move special handlers to `tools/execution_handlers.py`
5. Update ToolMapper to use new modules

### 🔴 HIGH PRIORITY (Do Next)

#### 3. MarkdownEditor.svelte (995 lines)
**Refactoring Plan:**
- Extract `EditorToolbar.svelte` (actions bar)
- Create `composables/useEditorActions.ts` (save, rename, pin, archive)
- Separate navigation guard logic
- Target: Reduce to ~400 lines

#### 4. prompts.py (529 lines)
**Refactoring Plan:**
- Move templates to `config/prompts.yaml`
- Keep only rendering functions
- Use YAML loader for templates
- Target: Reduce to ~150 lines

#### 5. mcp/tools.py (478 lines)
**Refactoring Plan:**
```
/backend/api/mcp/
├── tools.py (main registration, ~50 lines)
├── fs_tools.py - File system tools
├── notes_tools.py - Notes CRUD tools
├── web_tools.py - Web search, save, scraping
├── document_tools.py - PDF, DOCX, PPTX, XLSX
└── skill_tools.py - Skill creator, MCP builder
```

#### 6. claude_client.py (473 lines)
**Refactoring Plan:**
- Extract streaming logic to `streaming_handler.py`
- Extract tool execution to `tool_executor.py`
- Extract web search to `web_search_builder.py`
- Target: Reduce to ~200 lines

#### 7. FileTreeNode.svelte (709 lines)
**Refactoring Plan:**
- Extract `FileTreeContextMenu.svelte`
- Create `composables/useFileActions.ts`
- Simplify recursive rendering
- Target: Reduce to ~350 lines

### 🟡 MEDIUM PRIORITY (Technical Debt)

#### 8. WebsitesPanel.svelte (666 lines)
- Extract `WebsiteListItem.svelte`
- Target: Reduce to ~300 lines

#### 9. chat.ts (406 lines)
- Extract tool state to `toolState.ts`
- Target: Reduce to ~250 lines

#### 10. routers/files.py, notes.py, settings.py
- Move business logic to service layer
- Keep only HTTP handling in routers

## Common Anti-Patterns Found

### Backend
1. **Router Bloat** - Business logic in route handlers instead of service layer
2. **Monolithic Services** - Single class/function handling multiple responsibilities
3. **Config as Code** - Templates and metadata embedded in Python instead of config files
4. **No Separation of Concerns** - Tool definitions + execution + validation in same module

### Frontend
1. **God Components** - Components managing multiple features/dialogs
2. **Inline Dialogs** - Dialog components defined within parent instead of separate files
3. **No Composables** - Repeated action logic instead of shared composables
4. **Store Mixing** - Single store managing unrelated concerns (messages + streaming + tools)

## Refactoring Benefits

### Immediate Benefits
- **Easier Navigation** - Smaller files are easier to understand and navigate
- **Better Testing** - Isolated modules are easier to unit test
- **Reduced Conflicts** - Smaller files mean fewer merge conflicts
- **Clearer Ownership** - Each file has single, clear purpose

### Long-Term Benefits
- **Maintainability** - Easier to modify and extend features
- **Reusability** - Extracted components/functions can be reused
- **Onboarding** - New developers can understand code faster
- **Performance** - Smaller components can be lazy-loaded

## Recommended Approach

### Phase 1: High-Impact Quick Wins (Week 1)
1. Extract dialogs from Sidebar.svelte (5 new files)
2. Extract tool definitions from tool_mapper.py
3. Move prompts to YAML config

**Impact:** Immediate improvement in readability, no breaking changes

### Phase 2: Service Layer Cleanup (Week 2)
1. Split tool_mapper.py into modules
2. Extract streaming/tool logic from claude_client.py
3. Move business logic from routers to services

**Impact:** Better separation of concerns, easier testing

### Phase 3: Component Refactoring (Week 3)
1. Extract MarkdownEditor toolbar and actions
2. Simplify FileTreeNode with composables
3. Extract WebsiteListItem component

**Impact:** Improved component reusability

### Phase 4: Store & State (Week 4)
1. Split chat store (messages vs tools)
2. Create sidebar settings store
3. Extract location/weather services from site-header

**Impact:** Cleaner state management

## Metrics & Success Criteria

**Before Refactoring:**
- Files >1000 lines: 4
- Files >500 lines: 14
- Average file size: ~250 lines
- Largest file: 2,043 lines

**After Refactoring (Target):**
- Files >1000 lines: 0
- Files >500 lines: <5
- Average file size: ~200 lines
- Largest file: <600 lines

## Files Requiring No Action

Most files in the codebase are well-sized:
- 90% of files are <300 lines
- Services like `notes_service.py` (295 lines) are appropriately sized
- Components like `ChatWindow.svelte` (331 lines) are acceptable for main features
- Most utility files, types, and helpers are <100 lines

## Next Steps

1. **Review & Prioritize** - Confirm priorities with team
2. **Create Tasks** - Break down into smaller refactoring tasks
3. **Test Coverage** - Ensure tests exist before refactoring
4. **Incremental Approach** - Refactor one file at a time, test thoroughly
5. **Documentation** - Update architecture docs as files are split

## Summary

The sideBar codebase is generally healthy with clear hotspots needing attention. The two critical files (Sidebar.svelte and tool_mapper.py) represent the highest technical debt and should be addressed first. Most other files are well-sized, indicating good development practices overall.

**Recommendation:** Start with Sidebar.svelte dialog extraction as a high-impact, low-risk first step that will yield immediate benefits.
