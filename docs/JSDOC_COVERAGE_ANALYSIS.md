# JSDoc Coverage Analysis

**Date**: 2025-12-28
**Scope**: Frontend TypeScript codebase (`/src/lib`)
**Files Analyzed**: 17 TypeScript files

---

## Executive Summary

### Current State

| Category | With JSDoc | Without JSDoc | Coverage |
|----------|-----------|---------------|----------|
| **Functions** | 0 | 24 | **0.0%** ❌ |
| **Classes** | 0 | 2 | **0.0%** ❌ |
| **Methods** | 1 | 31 | **3.1%** ❌ |

**Total Items**: 58
**Documented**: 1
**Overall Coverage**: **1.7%** ❌

### Key Findings

❌ **Critical gaps:**
- No function documentation
- No class documentation
- Minimal method documentation (1 out of 32)

⚠️ **Priority areas** (most missing docs):
1. `services/api.ts` - 19 missing (API methods)
2. `services/memories.ts` - 11 missing (includes class)
3. `components/left-sidebar/panels/settingsApi.ts` - 6 missing

---

## Top Offenders

### 1. services/api.ts (19 missing)

**Impact**: Critical - These are the main API service methods used throughout the app

Missing documentation on:
- `ConversationsAPI` class methods: `create`, `list`, `get`, `addMessage`, `update`, `delete`, `search`
- `NotesAPI` class methods: `listTree`, `search`
- `WebsitesAPI` class methods: `list`, `get`, `search`

**Priority**: **HIGH** - Document immediately

**Example fix needed**:
```typescript
/**
 * Create a new conversation.
 *
 * @param title - The conversation title (defaults to "New Chat")
 * @returns Promise resolving to the created conversation object
 * @throws Error if API request fails
 */
async create(title: string = 'New Chat'): Promise<Conversation> {
  // ...
}
```

### 2. services/memories.ts (11 missing)

**Impact**: High - Core memory management API

Missing:
- `MemoriesAPI` class documentation
- All 10 API methods

**Priority**: **HIGH**

### 3. components/left-sidebar/panels/settingsApi.ts (6 missing)

**Impact**: Medium - Settings management functions

Missing:
- `fetchSettings`
- `saveSettings`
- `fetchSkills`
- `fetchLocationSuggestions`
- `uploadProfileImage`
- `deleteProfileImage`

**Priority**: **MEDIUM**

### 4. api/sse.ts (3 missing)

**Impact**: High - Critical streaming infrastructure

Missing:
- `SSEClient` class documentation
- Error handling methods

**Priority**: **HIGH**

**Note**: Already has good JSDoc on the `connect` method, just needs class docs and other methods

### 5. utils/* (9 missing across 3 files)

**Impact**: Medium - Utility functions

Files:
- `utils/scratchpad.ts` (3 missing)
- `utils/theme.ts` (3 missing)
- `components/left-sidebar/panels/settingsUtils.ts` (2 missing)

**Priority**: **MEDIUM**

---

## Detailed Breakdown by Category

### 1. API Services (Critical for Development)

**Current State**: 0% coverage

Files:
- `services/api.ts` - Main API client
- `services/memories.ts` - Memories API

**Why critical**:
- Used throughout the entire app
- Complex async operations
- Error handling needs documentation
- New developers need to understand return types and errors

**Recommendation**: Document ALL exported API methods with:
- Parameter descriptions
- Return value format
- Error conditions
- Usage examples

### 2. Stores (Important for State Management)

**Current State**: Some coverage in conversations.ts

Files analyzed:
- `stores/conversations.ts` - Has inline comments on some methods

**Why important**:
- Central state management
- Complex reactive patterns
- Multiple methods per store

**Recommendation**: Document:
- Store creation functions
- All store methods (load, update, delete, etc.)
- Derived stores
- State shape and behavior

### 3. Utilities (Supporting Functions)

**Current State**: 0% coverage

Files:
- `utils/scratchpad.ts`
- `utils/theme.ts`
- `components/left-sidebar/panels/settingsUtils.ts`

**Recommendation**: Document exported utilities, especially:
- Non-obvious transformations
- Functions with side effects
- Complex logic

### 4. SSE/Streaming (Critical Infrastructure)

**Current State**: Partial coverage (connect method documented)

File:
- `api/sse.ts`

**Why critical**:
- Complex WebSocket-like streaming
- Event handling
- Error recovery

**Recommendation**:
- Document `SSEClient` class
- Document all callback types
- Add usage examples

### 5. Hooks (Svelte 5 Runes)

**Current State**: 0% coverage

Files:
- `hooks/useEditorActions.ts`
- `hooks/useFileActions.ts`

**Why important**:
- Reusable composition
- New Svelte 5 runes pattern

**Recommendation**: Document with examples showing rune usage

---

## Recommended JSDoc Style

We use **JSDoc with TypeScript types** (types in code, descriptions in JSDoc):

```typescript
/**
 * Short one-line summary.
 *
 * Longer description explaining what this function does, any important
 * context, and how it relates to the broader system.
 *
 * @param param1 - Description of param1 (no type needed)
 * @param param2 - Description of param2 (optional, defaults to 0)
 * @returns Description of return value structure
 * @throws Error when validation fails
 *
 * @example
 * ```ts
 * const result = functionName('test', 42);
 * console.log(result);
 * ```
 */
async function functionName(param1: string, param2: number = 0): Promise<Result> {
  // ...
}
```

**Benefits:**
- Types from TypeScript (single source of truth)
- Descriptions from JSDoc (context and examples)
- IntelliSense in VS Code
- Generate docs with TypeDoc

---

## Tools for JSDoc Coverage

### 1. Custom Coverage Script (Implemented)

**Usage:**
```bash
npm run docs:jsdoc
```

**Features:**
- Counts functions, classes, methods
- Shows missing documentation by file
- Fails if below 60% threshold

### 2. ESLint Plugin (Configured)

**Usage:**
```bash
npm run lint        # Check
npm run lint:fix    # Auto-fix
```

**Configuration** (`eslint.config.js`):
```javascript
rules: {
  'jsdoc/require-jsdoc': ['warn', {
    require: {
      FunctionDeclaration: true,
      MethodDefinition: true,
      ClassDeclaration: true
    }
  }],
  'jsdoc/require-description': 'warn',
  'jsdoc/require-param': 'warn',
  'jsdoc/require-returns': 'warn'
}
```

### 3. TypeDoc (Installed)

Generate documentation website:

```bash
npm run docs
```

Output: `docs/` directory with HTML documentation

---

## Implementation Plan

### Phase 1: Critical API Services (High Priority)

**Status**: Not started
**Target**: 100% coverage for API services

Files:
- `services/api.ts` - All 3 classes and 13 methods
- `services/memories.ts` - Class + 10 methods

**Estimated effort**: 1-2 hours

### Phase 2: Infrastructure (High Priority)

**Status**: Partially complete
**Target**: Complete SSE client documentation

Files:
- `api/sse.ts` - Add class docs and remaining methods

**Estimated effort**: 30 minutes

### Phase 3: Utilities (Medium Priority)

**Status**: Not started
**Target**: 80% coverage for utilities

Files:
- `utils/scratchpad.ts`
- `utils/theme.ts`
- `components/left-sidebar/panels/settingsUtils.ts`
- `components/left-sidebar/panels/settingsApi.ts`

**Estimated effort**: 1 hour

### Phase 4: Hooks and Stores (Medium Priority)

**Status**: Not started
**Target**: 80% coverage

Files:
- `hooks/useEditorActions.ts`
- `hooks/useFileActions.ts`
- `components/editor/useMarkdownEditor.ts`

**Estimated effort**: 1 hour

---

## Automation and Enforcement

### Pre-commit Hook (Optional)

Add to `.git/hooks/pre-commit`:

```bash
#!/bin/bash
npm run docs:jsdoc
if [ $? -ne 0 ]; then
  echo "❌ JSDoc coverage below threshold. Please add documentation."
  exit 1
fi
```

### CI/CD Integration (Recommended)

Add to GitHub Actions:

```yaml
- name: Check JSDoc coverage
  run: |
    npm run docs:jsdoc
```

### VS Code Integration

Install extensions:
- **Document This** - Auto-generate JSDoc templates
- **TypeDoc** - Preview generated docs

---

## Success Metrics

### Target Coverage (Realistic for Frontend)

| Category | Current | Target | Priority |
|----------|---------|--------|----------|
| Functions | 0.0% | 60% | ⚠️ Focus |
| Classes | 0.0% | 100% | ⚠️ Focus |
| Methods | 3.1% | 60% | ⚠️ Focus |
| **Overall** | **1.7%** | **60%** | **Target** |

**Note**: Unlike backend (100% target), frontend targets 60% because:
- TypeScript types provide significant documentation
- Many simple getters/setters don't need docs
- Focus on exported public APIs

### Milestones

- [ ] **Phase 1 Complete**: API services at 100% (HIGH PRIORITY)
- [ ] **Phase 2 Complete**: SSE client at 100%
- [ ] **Phase 3 Complete**: Utilities at 80%
- [ ] **Phase 4 Complete**: Hooks/stores at 80%
- [ ] **Overall target**: 60%+ overall coverage

### Maintenance

- Run `npm run docs:jsdoc` before commits
- ESLint warns on missing JSDoc for new exports
- TypeDoc documentation regenerated on deploy

---

## Example Before/After

### Before (No Documentation)

```typescript
async create(title: string = 'New Chat'): Promise<Conversation> {
  const response = await fetch(`${this.baseUrl}/`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title })
  });
  if (!response.ok) throw new Error('Failed to create conversation');
  return response.json();
}
```

**Problems:**
- No description of what it does
- Error handling not documented
- Return format unclear
- No usage example

### After (Documented)

```typescript
/**
 * Create a new conversation.
 *
 * Posts to the API to create a conversation with the given title.
 * Returns the created conversation object with generated ID and metadata.
 *
 * @param title - The conversation title (defaults to "New Chat")
 * @returns Promise resolving to the created conversation object with:
 *   - id: Generated UUID
 *   - title: Conversation title
 *   - createdAt: ISO timestamp
 *   - updatedAt: ISO timestamp
 * @throws Error if API request fails (network error or 4xx/5xx response)
 *
 * @example
 * ```ts
 * const conversation = await conversationsAPI.create('Project Planning');
 * console.log(conversation.id); // "550e8400-e29b-41d4-a716-446655440000"
 * ```
 */
async create(title: string = 'New Chat'): Promise<Conversation> {
  const response = await fetch(`${this.baseUrl}/`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title })
  });
  if (!response.ok) throw new Error('Failed to create conversation');
  return response.json();
}
```

**Benefits:**
- Clear purpose
- Documented return structure
- Error conditions explained
- Usage example provided
- Shows up in IntelliSense

---

## Conclusion

### Current State Summary

- **Coverage**: 1.7% (extremely low)
- **Critical gaps**: API services, utilities, hooks
- **Tooling**: ✅ Installed and configured

### Recommended Action

**Immediate**: Focus on **Phase 1** (API services)
- `services/api.ts` - Highest impact, most used code
- `services/memories.ts` - Second highest impact

**After Phase 1**: Move to infrastructure (SSE) and utilities

### Expected Benefits

- **Developer Experience**: Faster onboarding, better IntelliSense
- **Type Safety**: Complements TypeScript types with context
- **Maintainability**: Self-documenting code, easier refactoring
- **Documentation**: Auto-generate docs website with TypeDoc

---

## Quick Commands

```bash
# Check coverage
npm run docs:jsdoc

# Run linter
npm run lint

# Auto-fix some issues
npm run lint:fix

# Generate docs website
npm run docs

# All checks
npm run lint && npm run docs:jsdoc
```

**Target**: 60%+ coverage across functions, classes, and methods.
