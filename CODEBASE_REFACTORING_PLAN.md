# Codebase Refactoring Plan - sideBar

## Overview

Comprehensive analysis of file sizes across the sideBar codebase to identify files that need refactoring based on length and complexity. This plan prioritizes technical debt reduction and improves code maintainability.

**Analysis Date:** December 27, 2025

## Executive Summary

**Current State:**
- **1 file >2000 lines** (Sidebar.svelte - 2,079 lines) - URGENT refactoring needed
- **3 files >1000 lines** (tool_mapper.py: 1,488, MarkdownEditor.svelte: 995, FileTreeNode.svelte: 709)
- **18 files >500 lines** requiring high-priority refactoring
- Technical debt is significant and requires immediate attention

**Key Patterns Identified:**
- Frontend: God components managing multiple dialogs and features
- Backend: Monolithic services mixing multiple responsibilities
- Routers mixing HTTP handling with business logic
- Configuration embedded in code instead of separate files
- Memory management adding complexity across multiple large files

**Progress to Date:**
- ✅ Some sidebar components extracted (NotesPanel, ConversationItem)
- ⚠️ Main components still require significant refactoring

## Top 12 Critical Files Needing Refactoring

### Backend

1. **`/backend/api/services/tool_mapper.py`** - **1,488 lines** 🚨 URGENT
   - Monolithic tool mapping service
   - Mixes tool definitions, execution, parameter mapping, skill metadata
   - **Recommended Split:**
     - `services/tools/definitions.py` - Tool schemas
     - `services/tools/skill_metadata.py` - Skill display info
     - `services/tools/parameter_mapper.py` - Parameter conversion
     - Keep only orchestration in ToolMapper

2. **`/backend/api/prompts.py`** - **534 lines** 🔴 HIGH
   - Mixes template configuration with rendering logic
   - **Recommended Split:**
     - `config/prompts.yaml` - Template strings
     - Keep only rendering functions in prompts.py

3. **`/backend/api/routers/files.py`** - **516 lines** 🔴 HIGH
   - Router with embedded business logic
   - **Recommendation:** Extract file tree logic to service layer

4. **`/backend/api/services/skill_file_ops.py`** - **507 lines** 🔴 HIGH
   - Handles skill file operations
   - **Recommendation:** Review and split into logical modules

5. **`/backend/api/services/claude_client.py`** - **492 lines** 🔴 HIGH
   - Handles streaming, tools, web search in single class
   - **Recommended Split:**
     - `services/streaming_handler.py`
     - `services/tool_executor.py`
     - `services/web_search_builder.py`

6. **`/backend/api/mcp/tools.py`** - **479 lines** 🔴 HIGH
   - Single massive function registering 15+ tools
   - **Recommended Split:**
     - `mcp/fs_tools.py`
     - `mcp/notes_tools.py`
     - `mcp/web_tools.py`
     - `mcp/document_tools.py`

7. **`/backend/api/services/memory_tool_handler.py`** - **473 lines** 🔴 HIGH
   - Handles memory tool operations
   - **Recommendation:** Consider integration with existing services or split by operation type

### Frontend

1. **`/frontend/src/lib/components/left-sidebar/Sidebar.svelte`** - **2,079 lines** 🚨 URGENT
   - God component managing navigation, notes, websites, settings
   - Multiple inline dialogs and modals
   - **Progress:** Some components extracted (NotesPanel, ConversationItem)
   - **Recommended Split:**
     - `dialogs/NewNoteDialog.svelte`
     - `dialogs/NewFolderDialog.svelte`
     - `dialogs/NewWebsiteDialog.svelte`
     - `dialogs/SaveChangesDialog.svelte`
     - `panels/SettingsPanel.svelte`
     - `stores/sidebarSettings.ts`

2. **`/frontend/src/lib/components/editor/MarkdownEditor.svelte`** - **995 lines** ⚠️ CRITICAL
   - Editor + note operations + navigation guards
   - **Recommended Split:**
     - `EditorToolbar.svelte` - Actions (save, rename, pin, etc.)
     - `composables/useEditorActions.ts` - Composable for handlers
     - Separate navigation guard logic

3. **`/frontend/src/lib/components/files/FileTreeNode.svelte`** - **709 lines** 🔴 HIGH
   - Recursive tree rendering + context menu + CRUD operations
   - **Recommended Split:**
     - `FileTreeContextMenu.svelte`
     - `composables/useFileActions.ts` - Composable for actions
     - Simplify recursive rendering

4. **`/frontend/src/lib/components/settings/MemorySettings.svelte`** - **691 lines** 🔴 HIGH
   - Memory configuration UI
   - **Recommendation:** Extract forms and dialogs, create sub-components

5. **`/frontend/src/lib/components/websites/WebsitesPanel.svelte`** - **687 lines** 🔴 HIGH
   - List rendering + context menus + operations
   - **Recommendation:** Extract `WebsiteListItem.svelte` and context menu

## Detailed Analysis by Category

### Backend Files >300 Lines

| File | Lines | Category | Priority | Issue |
|------|-------|----------|----------|-------|
| `services/tool_mapper.py` | 1,488 | Service | 🚨 URGENT | Monolithic tool service |
| `prompts.py` | 534 | Config | 🔴 HIGH | Config + logic mixed |
| `routers/files.py` | 516 | Router | 🔴 HIGH | Business logic in router |
| `services/skill_file_ops.py` | 507 | Service | 🔴 HIGH | Skill file operations |
| `services/claude_client.py` | 492 | Service | 🔴 HIGH | Multiple responsibilities |
| `mcp/tools.py` | 479 | Tools | 🔴 HIGH | Single massive function |
| `services/memory_tool_handler.py` | 473 | Service | 🔴 HIGH | Memory tool operations |
| `routers/notes.py` | 388 | Router | 🟡 MEDIUM | Business logic in router |
| `services/websites_service.py` | 351 | Service | 🟡 MEDIUM | Service complexity growing |
| `services/notes_service.py` | 330 | Service | 🟡 MEDIUM | Service complexity growing |
| `routers/settings.py` | 325 | Router | 🟡 MEDIUM | File upload + defaults |
| `routers/chat.py` | 302 | Router | ✅ OK | Could extract streaming |

### Frontend Files >300 Lines

| File | Lines | Category | Priority | Issue |
|------|-------|----------|----------|-------|
| `left-sidebar/Sidebar.svelte` | 2,079 | Component | 🚨 URGENT | God component with multiple dialogs |
| `editor/MarkdownEditor.svelte` | 995 | Component | 🚨 URGENT | Editor + operations |
| `files/FileTreeNode.svelte` | 709 | Component | 🔴 HIGH | Recursive + CRUD |
| `settings/MemorySettings.svelte` | 691 | Component | 🔴 HIGH | Memory configuration UI |
| `websites/WebsitesPanel.svelte` | 687 | Component | 🔴 HIGH | List + operations |
| `websites/WebsitesViewer.svelte` | 450 | Component | 🟡 MEDIUM | Viewer + actions |
| `stores/chat.ts` | 406 | Store | 🟡 MEDIUM | Multiple concerns |
| `scratchpad-popover.svelte` | 369 | Component | ✅ OK | Self-contained |
| `site-header.svelte` | 366 | Component | 🟡 MEDIUM | Multiple services |
| `left-sidebar/ConversationItem.svelte` | 347 | Component | ✅ OK | Extracted component |
| `chat/ChatWindow.svelte` | 344 | Component | ✅ OK | Main feature component |
| `left-sidebar/NotesPanel.svelte` | 284 | Component | ✅ OK | Extracted component |

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

**Current State:**
- Files >1000 lines: 4
- Files >500 lines: 18
- Average file size: ~280 lines
- Largest file: 2,079 lines

**Refactoring Targets:**
- Files >1000 lines: 0
- Files >500 lines: <5
- Average file size: ~200 lines
- Largest file: <600 lines

**Success Metrics:**
- ✅ Each dialog extracted from Sidebar reduces file by ~100-150 lines
- ✅ tool_mapper split should reduce to <300 lines orchestration code
- ✅ All routers should be <300 lines (business logic moved to services)
- ✅ Component extraction improves testability and reusability

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

The sideBar codebase has significant technical debt concentrated in a small number of large files. The two most critical files (Sidebar.svelte at 2,079 lines and tool_mapper.py at 1,488 lines) represent the highest priority for refactoring.

**Positive Progress:**
- ✅ Some components extracted from Sidebar (NotesPanel, ConversationItem, SearchBar)
- ✅ Most files (>90%) are well-sized and maintainable

**Critical Issues:**
- 🚨 Sidebar.svelte (2,079 lines) - Multiple inline dialogs need extraction
- 🚨 tool_mapper.py (1,488 lines) - Monolithic service needs modularization
- 🔴 18 files >500 lines requiring attention
- 🔴 4 files >1000 lines blocking maintainability

**Action Required:**

This plan provides a systematic approach to reducing technical debt. Success depends on:

1. **Prioritizing refactoring work** - Allocate dedicated time for technical debt reduction
2. **Starting with high-impact changes** - Dialog extraction yields immediate benefits
3. **Incremental approach** - Refactor one file at a time, test thoroughly
4. **Preventing new debt** - Establish guidelines for maximum file sizes

## Implementation Plan

### Week 1: High-Impact Quick Wins

**Sidebar Dialog Extraction (Days 1-3)**
1. Extract `dialogs/NewNoteDialog.svelte`
2. Extract `dialogs/NewFolderDialog.svelte`
3. Extract `dialogs/NewWebsiteDialog.svelte`
4. Extract `dialogs/SaveChangesDialog.svelte`
5. **Target:** Reduce Sidebar.svelte by ~400 lines

**Settings Panel Extraction (Days 4-5)**
1. Extract `panels/SettingsPanel.svelte`
2. Create `stores/sidebarSettings.ts`
3. **Target:** Reduce Sidebar.svelte by ~300 lines

**Expected Impact:** Sidebar.svelte reduced from 2,079 to ~1,400 lines

### Week 2: Backend Service Refactoring

**tool_mapper.py Modularization (Days 1-3)**
1. Create `services/tools/` directory
2. Extract `definitions.py` - Tool schemas
3. Extract `skill_metadata.py` - Skill display information
4. Extract `parameter_mapper.py` - Parameter conversion logic
5. **Target:** Reduce tool_mapper.py to <300 lines orchestration

**prompts.py Configuration (Days 4-5)**
1. Create `config/prompts.yaml`
2. Move all template strings to YAML
3. Keep only rendering functions in prompts.py
4. **Target:** Reduce prompts.py from 534 to ~150 lines

**Expected Impact:** 2 major backend files refactored, improved testability

### Week 3: Component & Router Cleanup

**MarkdownEditor Simplification (Days 1-2)**
1. Extract `EditorToolbar.svelte`
2. Create `composables/useEditorActions.ts`
3. **Target:** Reduce from 995 to ~600 lines

**Router Refactoring (Days 3-5)**
1. Extract business logic from `routers/files.py` to `services/files_service.py`
2. Extract business logic from `routers/notes.py` to `services/notes_service.py`
3. **Target:** All routers <300 lines

**Expected Impact:** Cleaner separation of concerns, easier testing

### Ongoing Practices

**File Size Guidelines:**
- Components: Target <500 lines, max 800 lines
- Services: Target <400 lines, max 600 lines
- Routers: Target <200 lines, max 300 lines

**Before Adding Features:**
- Check if target file is >500 lines
- If yes, extract components/functions first
- Keep technical debt from accumulating
