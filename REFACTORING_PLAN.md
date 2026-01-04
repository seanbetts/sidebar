# sideBar Refactoring Plan

**Date**: 2026-01-04
**Status**: Active
**Version**: 1.0

---

## Executive Summary

**Verdict: SELECTIVE REFACTORING RECOMMENDED**

This codebase is **well-architected and production-ready**, but has accumulated technical debt that warrants targeted refactoring. This is not a "tear it down and rebuild" situation—it's a "strategic cleanup and modernization" effort.

**Key Metrics:**
- **Backend**: 16,213 LOC across 35 test files
- **Frontend**: 27,667 LOC with **23 test files** (stores/services + flows coverage in place)
- **Architecture**: Modern stack (FastAPI, SvelteKit 5, TypeScript strict mode)
- **Code Quality**: Good documentation (80%+ docstring coverage), but some large files

**Technical Debt Score**: **6/10** (Moderate)

**Execution Notes (Updated)**:
- Prioritize **stores/services** testing first, then a small set of critical UI flows.
- Accept **lower UI component coverage** if stores/services + 2–3 flows are covered.
- **Hard‑fail in production** if SSL verification is disabled.
- **Defer large UI refactors** (e.g. ThingsTasksView, FilesPanel) until test scaffolding is in place.
- Refresh metrics (LOC/test counts) before kicking off implementation.

**Verification Notes (2026-01-04)**:
- Frontend client calls now use `/api/v1/*` via a SvelteKit `/api/v1/*` proxy route.
- WorkspaceService refactor verified: notes/files routers now call workspace services; shared base removes duplicated logic.
- Performance sanity checked: no additional background polling introduced; endpoints remain proxied without extra hops.
- Duplication reduction verified: notes/files workspace operations now share a single service base; Things/UniversalViewer refactors remove repeated header/body logic.
- Performance verification: `/api/v1` proxy streams responses through without buffering; no new timers or polling were added during the refactor.

---

## Table of Contents

1. [Priority Matrix](#priority-matrix)
2. [High Priority Issues](#high-priority-issues)
3. [Medium Priority Issues](#medium-priority-issues)
4. [Low Priority Issues](#low-priority-issues)
5. [Strengths to Preserve](#strengths-to-preserve)
6. [Refactoring Roadmap](#refactoring-roadmap)
7. [Implementation Details](#implementation-details)
8. [Testing Requirements](#testing-requirements)
9. [Migration Risks](#migration-risks)
10. [Acceptance Criteria](#acceptance-criteria)

---

## Priority Matrix

### 🔴 HIGH PRIORITY (Do Soon)

1. **Critical: Frontend Testing Gap**
2. **Security: SSL Verification Disabled**
3. **Refactor: Large Component Files**

### 🟡 MEDIUM PRIORITY (Next Quarter)

4. **Code Duplication: Workspace Services**
5. **Error Handling Standardization**
6. **API Versioning Strategy**

### 🟢 LOW PRIORITY (Future Improvements)

7. **Observability Enhancement**
8. **Complex File Refactoring**

---

## High Priority Issues

### 1. Frontend Testing Gap (CRITICAL)

#### Current State
- 23 test files focused on stores/services + critical flows
- Limited UI component coverage (still acceptable for this phase)
- Store/service coverage >= 70% with CI thresholds

#### Risk Assessment
- **Severity**: CRITICAL
- **Impact**: High risk for regressions, difficult to refactor confidently
- **Effort**: Medium-High (4-8 weeks, depending on scope of UI coverage)

#### Implementation Plan

**Phase 1: Test Infrastructure Setup**

```bash
# Ensure Vitest is properly configured
cd frontend
npm install --save-dev @vitest/ui @vitest/coverage-v8
```

Create test utilities:

```typescript
// frontend/src/tests/utils/test-utils.ts
import { render } from '@testing-library/svelte';
import { vi } from 'vitest';
import type { ComponentProps } from 'svelte';

export function renderWithStores<T>(
  component: any,
  props?: ComponentProps<T>,
  stores?: Record<string, any>
) {
  // Mock stores
  if (stores) {
    Object.entries(stores).forEach(([name, value]) => {
      vi.mock(`$lib/stores/${name}`, () => ({
        [name]: { subscribe: vi.fn((fn) => fn(value)) }
      }));
    });
  }

  return render(component, { props });
}

export const mockFetch = (data: any, ok = true) => {
  global.fetch = vi.fn(() =>
    Promise.resolve({
      ok,
      json: async () => data,
      text: async () => JSON.stringify(data)
    } as Response)
  );
};
```

**Phase 2: Priority Test Targets**

Create tests in this order:

1. **Critical User Flows** (Week 3-4)

```typescript
// frontend/src/tests/flows/chat-streaming.test.ts
import { describe, it, expect, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import ChatInterface from '$lib/components/chat/ChatInterface.svelte';

describe('Chat Streaming Flow', () => {
  it('should send message and receive streaming response', async () => {
    const user = userEvent.setup();

    // Mock SSE stream
    const mockEventSource = vi.fn();
    global.EventSource = mockEventSource;

    render(ChatInterface);

    const input = screen.getByPlaceholderText(/type a message/i);
    await user.type(input, 'Hello Claude');
    await user.keyboard('{Enter}');

    await waitFor(() => {
      expect(screen.getByText('Hello Claude')).toBeInTheDocument();
    });
  });

  it('should handle streaming errors gracefully', async () => {
    // Test error handling
  });
});
```

```typescript
// frontend/src/tests/flows/file-upload.test.ts
import { describe, it, expect } from 'vitest';
import { render, screen, waitFor } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import FileUpload from '$lib/components/files/FileUpload.svelte';

describe('File Upload Flow', () => {
  it('should upload file and show progress', async () => {
    const user = userEvent.setup();
    render(FileUpload);

    const file = new File(['test content'], 'test.txt', { type: 'text/plain' });
    const input = screen.getByLabelText(/upload file/i);

    await user.upload(input, file);

    await waitFor(() => {
      expect(screen.getByText(/uploading/i)).toBeInTheDocument();
    });
  });
});
```

```typescript
// frontend/src/tests/flows/authentication.test.ts
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import AuthFlow from '$lib/components/auth/AuthFlow.svelte';

describe('Authentication Flow', () => {
  it('should authenticate user with valid credentials', async () => {
    const user = userEvent.setup();
    render(AuthFlow);

    await user.type(screen.getByLabelText(/email/i), 'test@example.com');
    await user.type(screen.getByLabelText(/password/i), 'password123');
    await user.click(screen.getByRole('button', { name: /sign in/i }));

    // Assert success
  });
});
```

2. **Complex Components** (Week 4-5, only if needed)

```typescript
// frontend/src/tests/components/ThingsTasksView.test.ts
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import ThingsTasksView from '$lib/components/things/ThingsTasksView.svelte';
import { thingsStore } from '$lib/stores/things';

describe('ThingsTasksView', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('should load and display tasks', async () => {
    const mockTasks = [
      { id: '1', title: 'Test Task', status: 'open' }
    ];

    vi.spyOn(thingsStore, 'loadTasks').mockResolvedValue(mockTasks);

    render(ThingsTasksView);

    await waitFor(() => {
      expect(screen.getByText('Test Task')).toBeInTheDocument();
    });
  });

  it('should complete task when checked', async () => {
    const user = userEvent.setup();
    const mockComplete = vi.fn();
    vi.spyOn(thingsStore, 'completeTask').mockImplementation(mockComplete);

    render(ThingsTasksView);

    const checkbox = screen.getByRole('checkbox', { name: /test task/i });
    await user.click(checkbox);

    expect(mockComplete).toHaveBeenCalledWith('1');
  });

  it('should handle task search', async () => {
    const user = userEvent.setup();
    render(ThingsTasksView);

    const searchInput = screen.getByPlaceholderText(/search tasks/i);
    await user.type(searchInput, 'important');

    await waitFor(() => {
      // Assert filtered results
    });
  });
});
```

```typescript
// frontend/src/tests/components/UniversalViewer.test.ts
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import UniversalViewer from '$lib/components/files/UniversalViewer.svelte';

describe('UniversalViewer', () => {
  it('should render PDF viewer for PDF files', async () => {
    render(UniversalViewer, {
      props: {
        file: { name: 'test.pdf', mimeType: 'application/pdf', url: '/test.pdf' }
      }
    });

    expect(screen.getByTestId('pdf-viewer')).toBeInTheDocument();
  });

  it('should render image viewer for image files', async () => {
    render(UniversalViewer, {
      props: {
        file: { name: 'test.png', mimeType: 'image/png', url: '/test.png' }
      }
    });

    expect(screen.getByRole('img')).toBeInTheDocument();
  });

  it('should show error for unsupported file types', async () => {
    render(UniversalViewer, {
      props: {
        file: { name: 'test.xyz', mimeType: 'application/unknown', url: '/test.xyz' }
      }
    });

    expect(screen.getByText(/unsupported file type/i)).toBeInTheDocument();
  });
});
```

3. **State Management** (Week 1-2, highest priority)

```typescript
// frontend/src/tests/stores/tree.test.ts
import { describe, it, expect, beforeEach } from 'vitest';
import { get } from 'svelte/store';
import { treeStore } from '$lib/stores/tree';

describe('Tree Store', () => {
  beforeEach(() => {
    treeStore.reset();
  });

  it('should initialize with empty tree', () => {
    const state = get(treeStore);
    expect(state.nodes).toEqual([]);
  });

  it('should add node to tree', () => {
    treeStore.addNode({ id: '1', name: 'Root', children: [] });

    const state = get(treeStore);
    expect(state.nodes).toHaveLength(1);
    expect(state.nodes[0].name).toBe('Root');
  });

  it('should expand and collapse nodes', () => {
    treeStore.addNode({ id: '1', name: 'Root', children: [] });
    treeStore.toggleExpanded('1');

    const state = get(treeStore);
    expect(state.expanded).toContain('1');

    treeStore.toggleExpanded('1');
    expect(get(treeStore).expanded).not.toContain('1');
  });
});
```

```typescript
// frontend/src/tests/stores/chatStore.test.ts
import { describe, it, expect } from 'vitest';
import { get } from 'svelte/store';
import { chatStore } from '$lib/stores/chatStore';

describe('Chat Store', () => {
  it('should add message to conversation', () => {
    chatStore.addMessage({
      id: '1',
      role: 'user',
      content: 'Hello',
      timestamp: new Date()
    });

    const state = get(chatStore);
    expect(state.messages).toHaveLength(1);
  });

  it('should stream assistant response', async () => {
    chatStore.startStream('conv-1');
    chatStore.appendToStream('Hello ');
    chatStore.appendToStream('world');
    chatStore.endStream();

    const state = get(chatStore);
    const lastMessage = state.messages[state.messages.length - 1];
    expect(lastMessage.content).toBe('Hello world');
  });
});
```

4. **API Integration** (Week 2-3)

```typescript
// frontend/src/tests/services/api-client.test.ts
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { ApiClient } from '$lib/services/api-client';

describe('ApiClient', () => {
  let client: ApiClient;

  beforeEach(() => {
    client = new ApiClient('http://localhost:8000');
  });

  it('should send chat message', async () => {
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: true,
        json: async () => ({ message: 'Response' })
      } as Response)
    );

    const response = await client.sendMessage('Hello');
    expect(response.message).toBe('Response');
  });

  it('should handle API errors', async () => {
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: false,
        status: 500,
        json: async () => ({ error: 'Server error' })
      } as Response)
    );

    await expect(client.sendMessage('Hello')).rejects.toThrow();
  });
});
```

**Phase 3: Test Coverage Goals**

Update `frontend/package.json`:

```json
{
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "test:ui": "vitest --ui",
    "coverage": "vitest run --coverage"
  }
}
```

Configure coverage thresholds in `vitest.config.ts`:

```typescript
export default defineConfig({
  test: {
    environment: 'jsdom',
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html'],
      include: ['src/lib/stores/**', 'src/lib/services/**'],
      thresholds: {
        lines: 70,
        statements: 70,
        branches: 60,
        functions: 60
      }
    }
  }
});
```

#### Acceptance Criteria

- [x] At least 70% line coverage for stores/services
- [x] UI component coverage is “targeted” (critical flows only)
- [x] All critical user flows have integration tests
- [x] CI/CD pipeline runs tests on every PR
- [x] Coverage reports generated and reviewed

#### Files to Create

```
frontend/src/tests/
├── utils/
│   ├── test-utils.ts
│   ├── mock-stores.ts
│   └── mock-api.ts
├── flows/
│   ├── chat-streaming.test.ts
│   ├── file-upload.test.ts
│   └── authentication.test.ts
├── components/
│   ├── things/
│   │   └── ThingsTasksView.test.ts
│   ├── files/
│   │   ├── UniversalViewer.test.ts
│   │   └── FilesPanel.test.ts
│   └── chat/
│       └── ChatInterface.test.ts
├── stores/
│   ├── tree.test.ts
│   ├── chatStore.test.ts
│   └── conversationStore.test.ts
└── services/
    └── api-client.test.ts
```

---

### 2. Security: SSL Verification Disabled

#### Current State

**Location**: `backend/api/services/claude_client.py:22-27`

```python
# TEMPORARY WORKAROUND for corporate SSL interception
# TODO: Replace with proper CA certificate installation
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE

http_client = httpx.AsyncClient(
    verify=False,  # Disable SSL verification
    timeout=httpx.Timeout(60.0, connect=10.0)
)
```

#### Risk Assessment
- **Severity**: HIGH
- **Impact**: Vulnerable to MITM attacks in production
- **Effort**: Low (2-4 hours)

#### Implementation Plan

**Option 1: Environment-Based SSL Control (Recommended)**

```python
# backend/api/services/claude_client.py
import os
import ssl
from typing import Optional
import httpx
from anthropic import AsyncAnthropic
from api.config import Settings

class ClaudeClient:
    """Handles Claude API interactions with streaming and tool execution."""

    def __init__(self, settings: Settings):
        """Initialize the client with model settings and HTTP configuration.

        Args:
            settings: Application settings object.
        """
        self.client = AsyncAnthropic(
            api_key=settings.anthropic_api_key,
            http_client=self._create_http_client(settings)
        )
        self.model = settings.model_name
        self.tool_mapper = ToolMapper()

    def _create_http_client(self, settings: Settings) -> httpx.AsyncClient:
        """Create HTTP client with proper SSL configuration.

        Args:
            settings: Application settings object.

        Returns:
            Configured HTTP client.
        """
        # Production: Always verify SSL
        # Development: Optional bypass with explicit env var
        ssl_verify = True
        ssl_context = None

        if settings.environment == "development" and settings.disable_ssl_verify:
            # Only allow SSL bypass in development with explicit setting
            ssl_verify = False
            ssl_context = ssl.create_default_context()
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE
        elif settings.custom_ca_bundle:
            # Use custom CA bundle for corporate environments
            ssl_context = ssl.create_default_context()
            ssl_context.load_verify_locations(cafile=settings.custom_ca_bundle)

        return httpx.AsyncClient(
            verify=ssl_verify if not ssl_context else ssl_context,
            timeout=httpx.Timeout(60.0, connect=10.0)
        )
```

Update `backend/api/config.py`:

```python
from pydantic_settings import BaseSettings
from typing import Optional

class Settings(BaseSettings):
    """Application settings."""

    # Existing settings...
    anthropic_api_key: str
    model_name: str = "claude-sonnet-4"

    # SSL configuration
    environment: str = "production"
    disable_ssl_verify: bool = False
    custom_ca_bundle: Optional[str] = None

    class Config:
        env_file = ".env"

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        # Security: Never allow SSL bypass in production
        if self.environment == "production" and self.disable_ssl_verify:
            raise ValueError(
                "SSL verification cannot be disabled in production. "
                "Set ENVIRONMENT=development or provide CUSTOM_CA_BUNDLE."
            )
```

Update `.env.example`:

```bash
# Environment (production, development, staging)
ENVIRONMENT=production

# SSL Configuration
# ONLY use DISABLE_SSL_VERIFY=true in development environments
DISABLE_SSL_VERIFY=false

# For corporate environments with custom CA certificates
# CUSTOM_CA_BUNDLE=/path/to/corporate-ca-bundle.pem

# Or use standard environment variables
# REQUESTS_CA_BUNDLE=/path/to/ca-bundle.pem
# SSL_CERT_FILE=/path/to/ca-bundle.pem
```

**Option 2: System CA Bundle (Alternative)**

```python
# backend/api/services/claude_client.py
import certifi
import httpx

def _create_http_client(self, settings: Settings) -> httpx.AsyncClient:
    """Create HTTP client using system CA bundle."""
    # Use certifi for consistent CA bundle across platforms
    return httpx.AsyncClient(
        verify=certifi.where(),
        timeout=httpx.Timeout(60.0, connect=10.0)
    )
```

Add to `backend/pyproject.toml`:

```toml
dependencies = [
    # ... existing deps
    "certifi>=2023.0.0",
]
```

**Option 3: Docker-Based CA Installation**

Create `scripts/install-ca.sh`:

```bash
#!/bin/bash
# Script to install corporate CA certificate in Docker container

CA_CERT_URL="${CORPORATE_CA_URL:-}"
CA_CERT_PATH="/usr/local/share/ca-certificates/corporate-ca.crt"

if [ -n "$CA_CERT_URL" ]; then
    echo "Installing corporate CA certificate..."
    curl -o "$CA_CERT_PATH" "$CA_CERT_URL"
    update-ca-certificates
    echo "CA certificate installed successfully"
else
    echo "No corporate CA URL provided, skipping..."
fi
```

Update `Dockerfile`:

```dockerfile
FROM python:3.11-slim

# Install CA certificates package
RUN apt-get update && apt-get install -y ca-certificates curl && rm -rf /var/lib/apt/lists/*

# Copy CA installation script
COPY scripts/install-ca.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/install-ca.sh

# Install corporate CA if provided
ARG CORPORATE_CA_URL
RUN /usr/local/bin/install-ca.sh

# Continue with normal Dockerfile...
```

#### Testing

```python
# backend/tests/services/test_claude_client.py
import pytest
from api.services.claude_client import ClaudeClient
from api.config import Settings

def test_ssl_disabled_in_production_raises_error():
    """Test that SSL cannot be disabled in production."""
    with pytest.raises(ValueError, match="SSL verification cannot be disabled"):
        Settings(
            environment="production",
            disable_ssl_verify=True,
            anthropic_api_key="test-key"
        )

def test_ssl_can_be_disabled_in_development():
    """Test that SSL can be disabled in development."""
    settings = Settings(
        environment="development",
        disable_ssl_verify=True,
        anthropic_api_key="test-key"
    )
    client = ClaudeClient(settings)
    assert client is not None

def test_custom_ca_bundle_loaded():
    """Test that custom CA bundle is loaded."""
    settings = Settings(
        environment="production",
        custom_ca_bundle="/etc/ssl/certs/ca-bundle.crt",
        anthropic_api_key="test-key"
    )
    client = ClaudeClient(settings)
    # Verify SSL context uses custom CA
    assert client is not None
```

#### Acceptance Criteria

- [ ] SSL verification enabled by default in production
- [ ] Environment variable controls SSL bypass (dev only)
- [ ] Custom CA bundle support for corporate environments
- [ ] Error raised if SSL bypass attempted in production
- [ ] Tests verify SSL configuration behavior
- [ ] Documentation updated with SSL setup instructions

---

### 3. Refactor: Large Component Files

#### Current State

Large files that need decomposition:

| File | LOC | Issues |
|------|-----|--------|
| `frontend/src/lib/components/things/ThingsTasksView.svelte` | 1,464 | 86+ state variables, mixed concerns |
| `frontend/src/lib/components/files/UniversalViewer.svelte` | 1,355 | Multiple viewer types in one file |
| `frontend/src/lib/stores/tree.ts` | 1,237 | State + complex logic mixed |
| `frontend/src/lib/components/files/FilesPanel.svelte` | 1,085 | Many features in one component |

#### Risk Assessment
- **Severity**: MEDIUM-HIGH
- **Impact**: Hard to maintain, test, and extend
- **Effort**: High (6-8 weeks)

**Note**: Defer these refactors until test scaffolding is in place to avoid regressions.

#### Implementation Plan

#### 3.1 Refactor ThingsTasksView.svelte

**Current Structure** (1,464 LOC):
```svelte
<script lang="ts">
  // 86+ state variables
  let tasks, areas, projects, isLoading, searchPending, error, sections...
  let totalCount, hasLoaded, projectTitleById, areaTitleById...
  let selectionType, selection, busyTasks, refreshTimer...
  let showDueDialog, dueTask, dueDateValue, editingTaskId...
  // ... 70+ more variables

  // Mixed concerns: data fetching, UI state, business logic
  async function loadTasks() { /* 50+ lines */ }
  function handleComplete() { /* 30+ lines */ }
  function handleRename() { /* 40+ lines */ }
  // ... 30+ more functions
</script>

<div>
  <!-- 800+ lines of template -->
</div>
```

**Target Structure**:

```
frontend/src/lib/components/things/
├── ThingsTasksView.svelte           (200 LOC - orchestrator)
├── TaskListContainer.svelte         (150 LOC - list logic)
├── TaskItem.svelte                  (100 LOC - individual task)
├── TaskFilters.svelte               (120 LOC - filtering UI)
├── TaskDialogs/
│   ├── DueDateDialog.svelte        (80 LOC)
│   ├── MoveTaskDialog.svelte       (80 LOC)
│   ├── NotesDialog.svelte          (80 LOC)
│   └── DeleteDialog.svelte         (60 LOC)
├── TaskSections.svelte              (150 LOC - section grouping)
└── hooks/
    ├── useThingsTasks.ts           (300 LOC - data fetching)
    ├── useTaskActions.ts           (200 LOC - task operations)
    └── useTaskFilters.ts           (150 LOC - filter logic)
```

**Step 1: Extract Custom Hooks**

```typescript
// frontend/src/lib/components/things/hooks/useThingsTasks.ts
import { writable, derived } from 'svelte/store';
import type { ThingsTask, ThingsArea, ThingsProject, ThingsSelection } from '$lib/types/things';

export interface UseThingsTasksReturn {
  tasks: Readable<ThingsTask[]>;
  areas: Readable<ThingsArea[]>;
  projects: Readable<ThingsProject[]>;
  sections: Readable<TaskSection[]>;
  isLoading: Readable<boolean>;
  error: Readable<string>;
  loadTasks: (selection: ThingsSelection) => Promise<void>;
  refresh: () => Promise<void>;
}

export function useThingsTasks(initialSelection: ThingsSelection): UseThingsTasksReturn {
  const tasks = writable<ThingsTask[]>([]);
  const areas = writable<ThingsArea[]>([]);
  const projects = writable<ThingsProject[]>([]);
  const isLoading = writable(false);
  const error = writable('');

  const sections = derived(tasks, ($tasks) => {
    return groupTasksIntoSections($tasks);
  });

  async function loadTasks(selection: ThingsSelection) {
    isLoading.set(true);
    error.set('');

    try {
      const response = await fetch('/api/things/tasks', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ selection })
      });

      if (!response.ok) throw new Error('Failed to load tasks');

      const data = await response.json();
      tasks.set(data.tasks || []);
      areas.set(data.areas || []);
      projects.set(data.projects || []);
    } catch (err) {
      error.set(err.message);
    } finally {
      isLoading.set(false);
    }
  }

  async function refresh() {
    await loadTasks(initialSelection);
  }

  return {
    tasks,
    areas,
    projects,
    sections,
    isLoading,
    error,
    loadTasks,
    refresh
  };
}

function groupTasksIntoSections(tasks: ThingsTask[]): TaskSection[] {
  // Extract section grouping logic from main component
  const sections: TaskSection[] = [];
  const today = new Date();

  // Group by due date, project, etc.
  // ... (extracted from original component)

  return sections;
}
```

```typescript
// frontend/src/lib/components/things/hooks/useTaskActions.ts
import { writable } from 'svelte/store';
import type { ThingsTask } from '$lib/types/things';

export interface UseTaskActionsReturn {
  busyTasks: Readable<Set<string>>;
  completeTask: (taskId: string) => Promise<void>;
  renameTask: (taskId: string, newTitle: string) => Promise<void>;
  updateDueDate: (taskId: string, dueDate: string) => Promise<void>;
  moveTask: (taskId: string, listId: string) => Promise<void>;
  deleteTask: (taskId: string) => Promise<void>;
}

export function useTaskActions(onRefresh: () => Promise<void>): UseTaskActionsReturn {
  const busyTasks = writable(new Set<string>());

  async function executeAction(
    taskId: string,
    action: () => Promise<void>
  ) {
    busyTasks.update(set => {
      set.add(taskId);
      return set;
    });

    try {
      await action();
      await onRefresh();
    } finally {
      busyTasks.update(set => {
        set.delete(taskId);
        return set;
      });
    }
  }

  async function completeTask(taskId: string) {
    await executeAction(taskId, async () => {
      const response = await fetch('/api/things/tasks/complete', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ task_id: taskId })
      });

      if (!response.ok) throw new Error('Failed to complete task');
    });
  }

  async function renameTask(taskId: string, newTitle: string) {
    await executeAction(taskId, async () => {
      const response = await fetch('/api/things/tasks/rename', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ task_id: taskId, title: newTitle })
      });

      if (!response.ok) throw new Error('Failed to rename task');
    });
  }

  async function updateDueDate(taskId: string, dueDate: string) {
    await executeAction(taskId, async () => {
      const response = await fetch('/api/things/tasks/due-date', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ task_id: taskId, due_date: dueDate })
      });

      if (!response.ok) throw new Error('Failed to update due date');
    });
  }

  async function moveTask(taskId: string, listId: string) {
    await executeAction(taskId, async () => {
      const response = await fetch('/api/things/tasks/move', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ task_id: taskId, list_id: listId })
      });

      if (!response.ok) throw new Error('Failed to move task');
    });
  }

  async function deleteTask(taskId: string) {
    await executeAction(taskId, async () => {
      const response = await fetch('/api/things/tasks/delete', {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ task_id: taskId })
      });

      if (!response.ok) throw new Error('Failed to delete task');
    });
  }

  return {
    busyTasks,
    completeTask,
    renameTask,
    updateDueDate,
    moveTask,
    deleteTask
  };
}
```

**Step 2: Extract Dialog Components**

```svelte
<!-- frontend/src/lib/components/things/TaskDialogs/DueDateDialog.svelte -->
<script lang="ts">
  import { AlertDialog, AlertDialogContent, AlertDialogHeader, AlertDialogTitle, AlertDialogDescription, AlertDialogFooter, AlertDialogAction, AlertDialogCancel } from '$lib/components/ui/alert-dialog';
  import type { ThingsTask } from '$lib/types/things';

  export let open = false;
  export let task: ThingsTask | null = null;
  export let onConfirm: (taskId: string, dueDate: string) => Promise<void>;

  let dueDate = '';
  let saving = false;
  let error = '';

  $: if (task && open) {
    dueDate = task.dueDate || '';
    error = '';
  }

  async function handleConfirm() {
    if (!task) return;

    saving = true;
    error = '';

    try {
      await onConfirm(task.id, dueDate);
      open = false;
    } catch (err) {
      error = err.message;
    } finally {
      saving = false;
    }
  }
</script>

<AlertDialog bind:open>
  <AlertDialogContent>
    <AlertDialogHeader>
      <AlertDialogTitle>Set Due Date</AlertDialogTitle>
      <AlertDialogDescription>
        {#if task}
          Set due date for "{task.title}"
        {/if}
      </AlertDialogDescription>
    </AlertDialogHeader>

    <div class="space-y-4">
      <input
        type="date"
        bind:value={dueDate}
        class="w-full px-3 py-2 border rounded"
        disabled={saving}
      />

      {#if error}
        <p class="text-sm text-red-600">{error}</p>
      {/if}
    </div>

    <AlertDialogFooter>
      <AlertDialogCancel disabled={saving}>Cancel</AlertDialogCancel>
      <AlertDialogAction on:click={handleConfirm} disabled={saving}>
        {saving ? 'Saving...' : 'Set Due Date'}
      </AlertDialogAction>
    </AlertDialogFooter>
  </AlertDialogContent>
</AlertDialog>
```

**Step 3: Extract TaskItem Component**

```svelte
<!-- frontend/src/lib/components/things/TaskItem.svelte -->
<script lang="ts">
  import { Circle, Check, MoreHorizontal, CalendarClock } from 'lucide-svelte';
  import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger, DropdownMenuSeparator } from '$lib/components/ui/dropdown-menu';
  import type { ThingsTask } from '$lib/types/things';

  export let task: ThingsTask;
  export let busy = false;
  export let onComplete: (taskId: string) => void;
  export let onRename: (taskId: string) => void;
  export let onSetDueDate: (taskId: string) => void;
  export let onMove: (taskId: string) => void;
  export let onDelete: (taskId: string) => void;

  let editing = false;
  let editValue = task.title;

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter') {
      editing = false;
      if (editValue !== task.title) {
        onRename(task.id);
      }
    } else if (e.key === 'Escape') {
      editing = false;
      editValue = task.title;
    }
  }
</script>

<div class="flex items-center gap-2 py-2 px-3 hover:bg-gray-50 rounded" class:opacity-50={busy}>
  <button
    class="flex-shrink-0 w-5 h-5"
    disabled={busy}
    on:click={() => onComplete(task.id)}
  >
    {#if task.status === 'completed'}
      <Check class="w-5 h-5 text-green-600" />
    {:else}
      <Circle class="w-5 h-5 text-gray-400" />
    {/if}
  </button>

  {#if editing}
    <input
      type="text"
      bind:value={editValue}
      on:keydown={handleKeydown}
      on:blur={() => editing = false}
      class="flex-1 px-2 py-1 border rounded"
      autofocus
    />
  {:else}
    <button
      class="flex-1 text-left truncate"
      on:dblclick={() => editing = true}
    >
      {task.title}
    </button>
  {/if}

  {#if task.dueDate}
    <CalendarClock class="w-4 h-4 text-gray-400" />
    <span class="text-xs text-gray-500">{task.dueDate}</span>
  {/if}

  <DropdownMenu>
    <DropdownMenuTrigger>
      <MoreHorizontal class="w-4 h-4" />
    </DropdownMenuTrigger>
    <DropdownMenuContent>
      <DropdownMenuItem on:click={() => onRename(task.id)}>
        Rename
      </DropdownMenuItem>
      <DropdownMenuItem on:click={() => onSetDueDate(task.id)}>
        Set Due Date
      </DropdownMenuItem>
      <DropdownMenuItem on:click={() => onMove(task.id)}>
        Move to List
      </DropdownMenuItem>
      <DropdownMenuSeparator />
      <DropdownMenuItem on:click={() => onDelete(task.id)} class="text-red-600">
        Delete
      </DropdownMenuItem>
    </DropdownMenuContent>
  </DropdownMenu>
</div>
```

**Step 4: Refactored Main Component**

```svelte
<!-- frontend/src/lib/components/things/ThingsTasksView.svelte -->
<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { useThingsTasks } from './hooks/useThingsTasks';
  import { useTaskActions } from './hooks/useTaskActions';
  import TaskListContainer from './TaskListContainer.svelte';
  import TaskFilters from './TaskFilters.svelte';
  import DueDateDialog from './TaskDialogs/DueDateDialog.svelte';
  import MoveTaskDialog from './TaskDialogs/MoveTaskDialog.svelte';
  import NotesDialog from './TaskDialogs/NotesDialog.svelte';
  import DeleteDialog from './TaskDialogs/DeleteDialog.svelte';
  import type { ThingsSelection } from '$lib/types/things';

  // Simplified state - only orchestration concerns
  let selection: ThingsSelection = { type: 'today' };
  let refreshInterval: ReturnType<typeof setInterval> | null = null;

  // Dialog state
  let dueDateDialogOpen = false;
  let moveDialogOpen = false;
  let notesDialogOpen = false;
  let deleteDialogOpen = false;
  let activeTaskId: string | null = null;

  // Use custom hooks for complex logic
  const tasksQuery = useThingsTasks(selection);
  const taskActions = useTaskActions(tasksQuery.refresh);

  onMount(async () => {
    await tasksQuery.loadTasks(selection);

    // Auto-refresh every 5 minutes
    refreshInterval = setInterval(() => {
      tasksQuery.refresh();
    }, 5 * 60 * 1000);
  });

  onDestroy(() => {
    if (refreshInterval) clearInterval(refreshInterval);
  });

  // Dialog handlers
  function handleSetDueDate(taskId: string) {
    activeTaskId = taskId;
    dueDateDialogOpen = true;
  }

  function handleMove(taskId: string) {
    activeTaskId = taskId;
    moveDialogOpen = true;
  }

  function handleDelete(taskId: string) {
    activeTaskId = taskId;
    deleteDialogOpen = true;
  }

  $: activeTask = $tasksQuery.tasks.find(t => t.id === activeTaskId);
</script>

<div class="flex flex-col h-full">
  <TaskFilters
    bind:selection
    areas={$tasksQuery.areas}
    projects={$tasksQuery.projects}
    on:change={() => tasksQuery.loadTasks(selection)}
  />

  <TaskListContainer
    tasks={$tasksQuery.tasks}
    sections={$tasksQuery.sections}
    busyTasks={$taskActions.busyTasks}
    isLoading={$tasksQuery.isLoading}
    error={$tasksQuery.error}
    on:complete={(e) => taskActions.completeTask(e.detail.taskId)}
    on:rename={(e) => taskActions.renameTask(e.detail.taskId, e.detail.title)}
    on:setDueDate={(e) => handleSetDueDate(e.detail.taskId)}
    on:move={(e) => handleMove(e.detail.taskId)}
    on:delete={(e) => handleDelete(e.detail.taskId)}
  />

  <DueDateDialog
    bind:open={dueDateDialogOpen}
    task={activeTask}
    onConfirm={taskActions.updateDueDate}
  />

  <MoveTaskDialog
    bind:open={moveDialogOpen}
    task={activeTask}
    areas={$tasksQuery.areas}
    projects={$tasksQuery.projects}
    onConfirm={taskActions.moveTask}
  />

  <NotesDialog
    bind:open={notesDialogOpen}
    task={activeTask}
    onSave={taskActions.updateNotes}
  />

  <DeleteDialog
    bind:open={deleteDialogOpen}
    task={activeTask}
    onConfirm={taskActions.deleteTask}
  />
</div>
```

#### 3.2 Refactor UniversalViewer.svelte

**Target Structure**:

```
frontend/src/lib/components/files/viewers/
├── UniversalViewer.svelte          (150 LOC - orchestrator)
├── PdfViewer.svelte                (250 LOC)
├── ImageViewer.svelte              (150 LOC)
├── VideoViewer.svelte              (150 LOC)
├── AudioViewer.svelte              (150 LOC)
├── TextViewer.svelte               (200 LOC)
├── MarkdownViewer.svelte           (200 LOC)
├── CodeViewer.svelte               (180 LOC)
└── UnsupportedViewer.svelte        (80 LOC)
```

```svelte
<!-- frontend/src/lib/components/files/viewers/UniversalViewer.svelte -->
<script lang="ts">
  import PdfViewer from './PdfViewer.svelte';
  import ImageViewer from './ImageViewer.svelte';
  import VideoViewer from './VideoViewer.svelte';
  import AudioViewer from './AudioViewer.svelte';
  import TextViewer from './TextViewer.svelte';
  import MarkdownViewer from './MarkdownViewer.svelte';
  import CodeViewer from './CodeViewer.svelte';
  import UnsupportedViewer from './UnsupportedViewer.svelte';
  import type { FileMetadata } from '$lib/types/files';

  export let file: FileMetadata;

  $: viewerType = getViewerType(file.mimeType, file.name);

  function getViewerType(mimeType: string, filename: string): string {
    if (mimeType === 'application/pdf') return 'pdf';
    if (mimeType.startsWith('image/')) return 'image';
    if (mimeType.startsWith('video/')) return 'video';
    if (mimeType.startsWith('audio/')) return 'audio';
    if (mimeType === 'text/markdown' || filename.endsWith('.md')) return 'markdown';
    if (mimeType.startsWith('text/')) return 'text';
    if (isCodeFile(filename)) return 'code';
    return 'unsupported';
  }

  function isCodeFile(filename: string): boolean {
    const codeExtensions = ['.js', '.ts', '.py', '.java', '.cpp', '.rs', '.go'];
    return codeExtensions.some(ext => filename.endsWith(ext));
  }
</script>

<div class="viewer-container h-full">
  {#if viewerType === 'pdf'}
    <PdfViewer {file} />
  {:else if viewerType === 'image'}
    <ImageViewer {file} />
  {:else if viewerType === 'video'}
    <VideoViewer {file} />
  {:else if viewerType === 'audio'}
    <AudioViewer {file} />
  {:else if viewerType === 'markdown'}
    <MarkdownViewer {file} />
  {:else if viewerType === 'text'}
    <TextViewer {file} />
  {:else if viewerType === 'code'}
    <CodeViewer {file} />
  {:else}
    <UnsupportedViewer {file} />
  {/if}
</div>
```

#### 3.3 Refactor tree.ts Store

**Target Structure**:

```
frontend/src/lib/stores/tree/
├── index.ts                    (100 LOC - public API)
├── state.ts                    (150 LOC - store state)
├── actions.ts                  (300 LOC - tree operations)
├── selectors.ts                (200 LOC - derived state)
├── utils.ts                    (200 LOC - helper functions)
└── types.ts                    (100 LOC - type definitions)
```

```typescript
// frontend/src/lib/stores/tree/index.ts
/**
 * File tree store - public API
 * @module stores/tree
 */

export { treeStore } from './state';
export { TreeNode, TreeState, TreeSelection } from './types';
export {
  addNode,
  removeNode,
  updateNode,
  moveNode,
  toggleExpanded,
  selectNode
} from './actions';
export {
  getSelectedNode,
  getExpandedNodes,
  getNodePath,
  findNodeById
} from './selectors';
```

```typescript
// frontend/src/lib/stores/tree/state.ts
import { writable } from 'svelte/store';
import type { TreeState } from './types';

const initialState: TreeState = {
  nodes: [],
  expanded: new Set(),
  selected: null,
  loading: false,
  error: null
};

export const treeStore = writable<TreeState>(initialState);
```

```typescript
// frontend/src/lib/stores/tree/actions.ts
import { get } from 'svelte/store';
import { treeStore } from './state';
import type { TreeNode } from './types';
import { findNodeById, getNodePath } from './selectors';
import { insertNode, removeNodeById, updateNodeById } from './utils';

/**
 * Add a node to the tree
 */
export function addNode(node: TreeNode, parentId?: string) {
  treeStore.update(state => {
    const newNodes = insertNode(state.nodes, node, parentId);
    return { ...state, nodes: newNodes };
  });
}

/**
 * Remove a node from the tree
 */
export function removeNode(nodeId: string) {
  treeStore.update(state => {
    const newNodes = removeNodeById(state.nodes, nodeId);
    return { ...state, nodes: newNodes };
  });
}

/**
 * Update a node in the tree
 */
export function updateNode(nodeId: string, updates: Partial<TreeNode>) {
  treeStore.update(state => {
    const newNodes = updateNodeById(state.nodes, nodeId, updates);
    return { ...state, nodes: newNodes };
  });
}

/**
 * Toggle expanded state of a node
 */
export function toggleExpanded(nodeId: string) {
  treeStore.update(state => {
    const newExpanded = new Set(state.expanded);
    if (newExpanded.has(nodeId)) {
      newExpanded.delete(nodeId);
    } else {
      newExpanded.add(nodeId);
    }
    return { ...state, expanded: newExpanded };
  });
}

/**
 * Select a node
 */
export function selectNode(nodeId: string | null) {
  treeStore.update(state => ({
    ...state,
    selected: nodeId
  }));
}
```

#### Acceptance Criteria

- [x] ThingsTasksView.svelte reduced to < 300 LOC
- [x] UniversalViewer.svelte reduced to < 200 LOC
- [ ] tree.ts store split into logical modules
- [ ] FilesPanel.svelte reduced to < 400 LOC
- [ ] All extracted components have unit tests
- [ ] No functionality regression
- [x] Performance maintained or improved

---

## Medium Priority Issues

### 4. Code Duplication: Workspace Services

#### Current State

Multiple workspace services with similar patterns:

- `backend/api/services/files_workspace_service.py` (441 LOC)
- `backend/api/services/notes_workspace_service.py` (363 LOC)

Both implement:
- `list_tree(db, user_id) -> dict`
- `search(db, user_id, query) -> dict`

#### Implementation Plan

Create generic workspace abstraction:

```python
# backend/api/services/workspace_service.py
"""Generic workspace service abstraction."""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Generic, TypeVar, List, Dict, Any
from sqlalchemy.orm import Session

T = TypeVar('T')  # Model type


class WorkspaceService(ABC, Generic[T]):
    """Base class for workspace-facing services.

    Provides common patterns for tree listing, search, and CRUD operations
    scoped to user workspaces.
    """

    @abstractmethod
    def _query_items(
        self,
        db: Session,
        user_id: str,
        include_deleted: bool = False
    ) -> List[T]:
        """Query items for a user.

        Args:
            db: Database session.
            user_id: User ID to filter by.
            include_deleted: Whether to include soft-deleted items.

        Returns:
            List of items.
        """
        pass

    @abstractmethod
    def _build_tree_node(self, item: T) -> Dict[str, Any]:
        """Convert a model instance to a tree node.

        Args:
            item: Model instance.

        Returns:
            Tree node dictionary.
        """
        pass

    @abstractmethod
    def _search_items(
        self,
        db: Session,
        user_id: str,
        query: str,
        limit: int
    ) -> List[T]:
        """Search items for a user.

        Args:
            db: Database session.
            user_id: User ID to filter by.
            query: Search query string.
            limit: Maximum results to return.

        Returns:
            List of matching items.
        """
        pass

    def list_tree(
        self,
        db: Session,
        user_id: str,
        include_deleted: bool = False
    ) -> Dict[str, List[Dict[str, Any]]]:
        """List items as a tree structure.

        Args:
            db: Database session.
            user_id: User ID to filter by.
            include_deleted: Whether to include soft-deleted items.

        Returns:
            Tree structure with children array.
        """
        items = self._query_items(db, user_id, include_deleted)
        nodes = [self._build_tree_node(item) for item in items]
        return {"children": nodes}

    def search(
        self,
        db: Session,
        user_id: str,
        query: str,
        limit: int = 50
    ) -> Dict[str, List[Dict[str, Any]]]:
        """Search items.

        Args:
            db: Database session.
            user_id: User ID to filter by.
            query: Search query string.
            limit: Maximum results to return.

        Returns:
            Search results as list of items.
        """
        items = self._search_items(db, user_id, query, limit)
        results = [self._item_to_dict(item) for item in items]
        return {"results": results}

    @abstractmethod
    def _item_to_dict(self, item: T) -> Dict[str, Any]:
        """Convert item to dictionary representation.

        Args:
            item: Model instance.

        Returns:
            Dictionary representation.
        """
        pass
```

Refactor existing services:

```python
# backend/api/services/notes_workspace_service.py
"""Workspace-specific note operations for the notes API."""
from __future__ import annotations

from typing import List, Dict, Any
from sqlalchemy import or_
from sqlalchemy.orm import Session, load_only
from api.models.note import Note
from api.services.workspace_service import WorkspaceService
from api.services.notes_service import NotesService


class NotesWorkspaceService(WorkspaceService[Note]):
    """Workspace-facing note operations for the API layer."""

    def _query_items(
        self,
        db: Session,
        user_id: str,
        include_deleted: bool = False
    ) -> List[Note]:
        """Query notes for a user."""
        query = (
            db.query(Note)
            .options(load_only(Note.id, Note.title, Note.metadata_, Note.updated_at))
            .filter(Note.user_id == user_id)
        )

        if not include_deleted:
            query = query.filter(Note.deleted_at.is_(None))

        return query.order_by(Note.updated_at.desc()).all()

    def _build_tree_node(self, note: Note) -> Dict[str, Any]:
        """Convert note to tree node."""
        return NotesService.build_notes_tree([note])

    def _search_items(
        self,
        db: Session,
        user_id: str,
        query: str,
        limit: int
    ) -> List[Note]:
        """Search notes."""
        search_pattern = f"%{query}%"
        return (
            db.query(Note)
            .filter(
                Note.user_id == user_id,
                Note.deleted_at.is_(None),
                or_(
                    Note.title.ilike(search_pattern),
                    Note.content.ilike(search_pattern)
                )
            )
            .limit(limit)
            .all()
        )

    def _item_to_dict(self, note: Note) -> Dict[str, Any]:
        """Convert note to dictionary."""
        return {
            "id": note.id,
            "title": note.title,
            "content": note.content,
            "updated_at": note.updated_at.isoformat() if note.updated_at else None
        }
```

```python
# backend/api/services/files_workspace_service.py
"""Workspace file operations backed by ingestion."""
from __future__ import annotations

from typing import List, Dict, Any
from sqlalchemy.orm import Session
from api.models.file_ingestion import IngestedFile
from api.services.workspace_service import WorkspaceService


class FilesWorkspaceService(WorkspaceService[IngestedFile]):
    """Workspace-facing file operations for the API layer."""

    def _query_items(
        self,
        db: Session,
        user_id: str,
        include_deleted: bool = False
    ) -> List[IngestedFile]:
        """Query files for a user."""
        query = (
            db.query(IngestedFile)
            .filter(IngestedFile.user_id == user_id)
        )

        if not include_deleted:
            query = query.filter(IngestedFile.deleted_at.is_(None))

        return query.order_by(IngestedFile.updated_at.desc()).all()

    def _build_tree_node(self, file: IngestedFile) -> Dict[str, Any]:
        """Convert file to tree node."""
        return {
            "id": file.id,
            "name": file.path.split('/')[-1],
            "path": file.path,
            "type": "file",
            "size": file.size,
            "mimeType": file.mime_type
        }

    def _search_items(
        self,
        db: Session,
        user_id: str,
        query: str,
        limit: int
    ) -> List[IngestedFile]:
        """Search files."""
        search_pattern = f"%{query}%"
        return (
            db.query(IngestedFile)
            .filter(
                IngestedFile.user_id == user_id,
                IngestedFile.deleted_at.is_(None),
                IngestedFile.path.ilike(search_pattern)
            )
            .limit(limit)
            .all()
        )

    def _item_to_dict(self, file: IngestedFile) -> Dict[str, Any]:
        """Convert file to dictionary."""
        return {
            "id": file.id,
            "path": file.path,
            "size": file.size,
            "mime_type": file.mime_type,
            "updated_at": file.updated_at.isoformat() if file.updated_at else None
        }
```

#### Acceptance Criteria

- [x] Generic `WorkspaceService` base class created
- [x] `NotesWorkspaceService` refactored to use base class
- [x] `FilesWorkspaceService` refactored to use base class
- [ ] Tests verify behavior maintained
- [x] Code duplication reduced by ~30%

---

### 5. Error Handling Standardization

#### Current State

- 162 instances of `HTTPException` across 21 files
- No centralized error handling
- Inconsistent error response formats

#### Implementation Plan

**Step 1: Create Custom Exception Hierarchy**

```python
# backend/api/exceptions.py
"""Custom exception hierarchy for API errors."""
from typing import Optional, Dict, Any


class APIError(Exception):
    """Base exception for all API errors.

    Attributes:
        status_code: HTTP status code.
        code: Machine-readable error code.
        message: Human-readable error message.
        details: Optional additional error details.
    """

    def __init__(
        self,
        status_code: int,
        code: str,
        message: str,
        details: Optional[Dict[str, Any]] = None
    ):
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details = details or {}
        super().__init__(message)


# 400 errors
class BadRequestError(APIError):
    """Request validation failed."""

    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None):
        super().__init__(400, "BAD_REQUEST", message, details)


class ValidationError(APIError):
    """Input validation failed."""

    def __init__(self, field: str, message: str):
        super().__init__(
            400,
            "VALIDATION_ERROR",
            f"Validation failed for field '{field}': {message}",
            {"field": field}
        )


# 401 errors
class AuthenticationError(APIError):
    """Authentication failed."""

    def __init__(self, message: str = "Authentication required"):
        super().__init__(401, "AUTHENTICATION_REQUIRED", message)


class InvalidTokenError(APIError):
    """Invalid or expired token."""

    def __init__(self, message: str = "Invalid or expired token"):
        super().__init__(401, "INVALID_TOKEN", message)


# 403 errors
class PermissionDeniedError(APIError):
    """User lacks permission for this action."""

    def __init__(self, resource: str, action: str = "access"):
        super().__init__(
            403,
            "PERMISSION_DENIED",
            f"Permission denied to {action} {resource}",
            {"resource": resource, "action": action}
        )


# 404 errors
class NotFoundError(APIError):
    """Resource not found."""

    def __init__(self, resource: str, identifier: str):
        super().__init__(
            404,
            "NOT_FOUND",
            f"{resource} not found: {identifier}",
            {"resource": resource, "identifier": identifier}
        )


class NoteNotFoundError(NotFoundError):
    """Note not found."""

    def __init__(self, note_id: str):
        super().__init__("Note", note_id)


class ConversationNotFoundError(NotFoundError):
    """Conversation not found."""

    def __init__(self, conversation_id: str):
        super().__init__("Conversation", conversation_id)


class FileNotFoundError(NotFoundError):
    """File not found."""

    def __init__(self, file_path: str):
        super().__init__("File", file_path)


# 409 errors
class ConflictError(APIError):
    """Resource conflict."""

    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None):
        super().__init__(409, "CONFLICT", message, details)


# 500 errors
class InternalServerError(APIError):
    """Internal server error."""

    def __init__(self, message: str = "An internal error occurred"):
        super().__init__(500, "INTERNAL_ERROR", message)


class ExternalServiceError(APIError):
    """External service error."""

    def __init__(self, service: str, message: str):
        super().__init__(
            502,
            "EXTERNAL_SERVICE_ERROR",
            f"Error from {service}: {message}",
            {"service": service}
        )
```

**Step 2: Create Error Handler Middleware**

```python
# backend/api/middleware/error_handler.py
"""Error handling middleware."""
import logging
from fastapi import Request, status
from fastapi.responses import JSONResponse
from api.exceptions import APIError

logger = logging.getLogger(__name__)


async def api_error_handler(request: Request, exc: APIError) -> JSONResponse:
    """Handle APIError exceptions.

    Args:
        request: FastAPI request object.
        exc: API error exception.

    Returns:
        JSON error response.
    """
    # Log error for monitoring
    logger.error(
        f"API Error: {exc.code}",
        extra={
            "status_code": exc.status_code,
            "code": exc.code,
            "message": exc.message,
            "details": exc.details,
            "path": request.url.path,
            "method": request.method
        }
    )

    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "code": exc.code,
                "message": exc.message,
                "details": exc.details
            }
        }
    )


async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Handle unhandled exceptions.

    Args:
        request: FastAPI request object.
        exc: Unhandled exception.

    Returns:
        JSON error response.
    """
    logger.exception(
        "Unhandled exception",
        extra={
            "path": request.url.path,
            "method": request.method
        }
    )

    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "error": {
                "code": "INTERNAL_ERROR",
                "message": "An internal error occurred",
                "details": {}
            }
        }
    )
```

**Step 3: Register Error Handlers**

```python
# backend/api/main.py
from fastapi import FastAPI
from api.middleware.error_handler import api_error_handler, unhandled_exception_handler
from api.exceptions import APIError

app = FastAPI()

# Register error handlers
app.add_exception_handler(APIError, api_error_handler)
app.add_exception_handler(Exception, unhandled_exception_handler)
```

**Step 4: Update Router Code**

```python
# backend/api/routers/notes.py - BEFORE
from fastapi import HTTPException

@router.get("/{note_id}")
async def get_note(note_id: str, db: Session = Depends(get_db)):
    note = db.query(Note).filter(Note.id == note_id).first()
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")
    return note

# backend/api/routers/notes.py - AFTER
from api.exceptions import NoteNotFoundError

@router.get("/{note_id}")
async def get_note(note_id: str, db: Session = Depends(get_db)):
    note = db.query(Note).filter(Note.id == note_id).first()
    if not note:
        raise NoteNotFoundError(note_id)
    return note
```

#### Acceptance Criteria

- [x] Custom exception hierarchy created
- [x] Error handler middleware implemented
- [x] All routers updated to use custom exceptions
- [x] Error responses have consistent format
- [x] Error codes are documented

---

### 6. API Versioning Strategy

#### Current State

- API versioning now available under `/api/v1/*` with legacy routes still supported
- Breaking changes manageable via deprecation headers

#### Implementation Plan

**Step 1: Add Versioned Routes**

```python
# backend/api/main.py
from fastapi import FastAPI
from api.routers import chat, conversations, notes, files, settings

app = FastAPI(title="sideBar API", version="1.0.0")

# V1 API (current)
app.include_router(chat.router, prefix="/api/v1/chat", tags=["chat-v1"])
app.include_router(conversations.router, prefix="/api/v1/conversations", tags=["conversations-v1"])
app.include_router(notes.router, prefix="/api/v1/notes", tags=["notes-v1"])
app.include_router(files.router, prefix="/api/v1/files", tags=["files-v1"])
app.include_router(settings.router, prefix="/api/v1/settings", tags=["settings-v1"])

# Legacy routes (redirect to v1)
app.include_router(chat.router, prefix="/api/chat", tags=["chat-legacy"], deprecated=True)
app.include_router(conversations.router, prefix="/api/conversations", tags=["conversations-legacy"], deprecated=True)
app.include_router(notes.router, prefix="/api/notes", tags=["notes-legacy"], deprecated=True)
```

**Step 2: Add Deprecation Middleware**

```python
# backend/api/middleware/deprecation.py
"""Deprecation warning middleware."""
import logging
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

logger = logging.getLogger(__name__)

DEPRECATED_PATHS = {
    "/api/chat": "/api/v1/chat",
    "/api/conversations": "/api/v1/conversations",
    "/api/notes": "/api/v1/notes",
    "/api/files": "/api/v1/files"
}


class DeprecationMiddleware(BaseHTTPMiddleware):
    """Add deprecation warnings to legacy endpoints."""

    async def dispatch(self, request: Request, call_next):
        path = request.url.path

        # Check if path is deprecated
        for old_path, new_path in DEPRECATED_PATHS.items():
            if path.startswith(old_path):
                logger.warning(
                    f"Deprecated API path used: {path}",
                    extra={"client": request.client.host}
                )

                response = await call_next(request)
                response.headers["X-API-Deprecated"] = "true"
                response.headers["X-API-Deprecated-Path"] = old_path
                response.headers["X-API-New-Path"] = new_path
                response.headers["X-API-Sunset-Date"] = "2026-06-01"
                return response

        return await call_next(request)
```

**Step 3: Update Frontend API Client**

```typescript
// frontend/src/lib/services/api-client.ts
const API_VERSION = 'v1';
const BASE_URL = `/api/${API_VERSION}`;

export class ApiClient {
  private baseUrl: string;

  constructor(version: string = 'v1') {
    this.baseUrl = `/api/${version}`;
  }

  async sendMessage(message: string, conversationId?: string) {
    const response = await fetch(`${this.baseUrl}/chat/stream`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message, conversation_id: conversationId })
    });

    return response;
  }

  // ... other methods
}
```

#### Acceptance Criteria

- [x] V1 routes created with `/api/v1/` prefix
- [x] Legacy routes maintained with deprecation warnings
- [x] Deprecation middleware adds warning headers
- [x] Frontend updated to use V1 routes
- [x] API documentation shows versions

---

## Low Priority Issues

### 7. Observability Enhancement

#### Implementation Plan

**Add Prometheus Metrics**

```python
# backend/api/metrics.py
"""Prometheus metrics for monitoring."""
from prometheus_client import Counter, Histogram, Gauge
import time

# Request metrics
http_requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

http_request_duration_seconds = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration',
    ['method', 'endpoint']
)

# Chat metrics
chat_messages_total = Counter(
    'chat_messages_total',
    'Total chat messages sent'
)

chat_streaming_duration_seconds = Histogram(
    'chat_streaming_duration_seconds',
    'Duration of chat streaming responses'
)

# Tool execution metrics
tool_executions_total = Counter(
    'tool_executions_total',
    'Total tool executions',
    ['skill_id', 'status']
)

tool_execution_duration_seconds = Histogram(
    'tool_execution_duration_seconds',
    'Tool execution duration',
    ['skill_id']
)

# Database metrics
db_connections_active = Gauge(
    'db_connections_active',
    'Active database connections'
)

# Storage metrics
storage_operations_total = Counter(
    'storage_operations_total',
    'Total storage operations',
    ['operation', 'status']
)
```

**Add Metrics Middleware**

```python
# backend/api/middleware/metrics.py
"""Metrics collection middleware."""
import time
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware
from api.metrics import http_requests_total, http_request_duration_seconds


class MetricsMiddleware(BaseHTTPMiddleware):
    """Collect request metrics."""

    async def dispatch(self, request: Request, call_next):
        start_time = time.time()

        response = await call_next(request)

        duration = time.time() - start_time

        # Record metrics
        http_requests_total.labels(
            method=request.method,
            endpoint=request.url.path,
            status=response.status_code
        ).inc()

        http_request_duration_seconds.labels(
            method=request.method,
            endpoint=request.url.path
        ).observe(duration)

        return response
```

**Add Sentry for Error Tracking**

```python
# backend/api/main.py
import sentry_sdk
from sentry_sdk.integrations.fastapi import FastAPIIntegration
from sentry_sdk.integrations.sqlalchemy import SqlalchemyIntegration

if settings.sentry_dsn:
    sentry_sdk.init(
        dsn=settings.sentry_dsn,
        integrations=[
            FastAPIIntegration(),
            SqlalchemyIntegration()
        ],
        traces_sample_rate=0.1,
        profiles_sample_rate=0.1,
        environment=settings.environment
    )
```

---

---

## Strengths to Preserve

**Do NOT change these during refactoring:**

1. **Security Architecture**
   - Layered defense (container security, path jailing, audit logging)
   - Keep all security measures intact

2. **JSONB Message Storage**
   - Fast queries, atomic updates
   - Works well for single conversations

3. **SSE Streaming**
   - Simpler than WebSockets
   - Good browser compatibility

4. **Skill System**
   - Agent Skills specification
   - Subprocess sandboxing

5. **Type Safety**
   - TypeScript strict mode
   - Python type hints

6. **Documentation**
   - 80%+ docstring coverage
   - Maintain this standard

---

## Testing Requirements

### Backend Testing

All refactored code must include:

```python
# Test structure
backend/tests/
├── unit/
│   ├── test_workspace_service.py
│   ├── test_exceptions.py
│   └── test_cache.py
├── integration/
│   ├── test_chat_streaming.py
│   ├── test_file_upload.py
│   └── test_api_versioning.py
└── fixtures/
    └── ...
```

**Coverage Requirements:**
- Unit tests: 90%+ coverage
- Integration tests for all API endpoints
- Security tests for auth/permissions

### Frontend Testing

All refactored components must include:

```typescript
// Test structure
frontend/src/tests/
├── unit/
│   ├── components/
│   ├── stores/
│   └── utils/
├── integration/
│   └── flows/
└── e2e/ (future)
```

**Coverage Requirements:**
- Component tests: 70%+ coverage
- Store tests: 80%+ coverage
- Integration tests for critical flows

---

## Migration Risks & Mitigation

### Risk 1: Breaking Frontend During Component Refactor

**Probability**: Medium
**Impact**: High

**Mitigation:**
- Refactor one component at a time
- Write tests BEFORE refactoring
- Use feature flags to toggle new components
- Keep old code until new code is validated
- Run parallel deployments (A/B testing)

### Risk 2: API Changes Breaking Existing Clients

**Probability**: Low (with versioning)
**Impact**: High

**Mitigation:**
- Add versioning first (`/api/v1/`)
- Maintain backwards compatibility for 2-3 versions
- Use deprecation warnings in responses
- Document migration guide
- Monitor usage of deprecated endpoints

### Risk 3: Performance Regression

**Probability**: Medium
**Impact**: Medium

**Mitigation:**
- Benchmark before/after for critical paths
- Monitor SSE streaming latency
- Test with realistic data volumes
- Use profiling tools (py-spy, Chrome DevTools)
- Set performance budgets in CI

### Risk 4: Data Loss During Migration

**Probability**: Low
**Impact**: Critical

**Mitigation:**
- Backup database before major changes
- Test migrations on staging environment
- Use database transactions
- Implement rollback procedures
- Monitor error rates during deployment

---

## Acceptance Criteria

### Phase 1: Critical Fixes

- [x] Frontend test suite with 70%+ coverage
- [x] SSL verification properly configured
- [x] ThingsTasksView refactored to < 300 LOC
- [x] UniversalViewer refactored to < 200 LOC
- [ ] No functionality regressions
- [x] All tests passing

### Phase 2: Consolidation

- [x] WorkspaceService abstraction implemented
- [x] Custom exception hierarchy in use
- [x] API versioning implemented
- [x] Deprecation warnings working
- [x] Code duplication reduced by 30%

### Phase 3: Modernization

- [x] Prometheus metrics collecting data
- [x] Sentry error tracking active
- [x] Performance maintained or improved

---

## Implementation Timeline

### Phase 1: Critical Fixes (2-3 weeks)

**Week 1:**
- [x] Set up frontend testing infrastructure
- [x] Write tests for critical flows
- [x] Fix SSL verification issue

**Week 2:**
- [x] Refactor ThingsTasksView component
- [ ] Extract custom hooks
- [ ] Extract dialog components

**Week 3:**
- [x] Refactor UniversalViewer component
- [ ] Split into viewer components
- [ ] Add component tests

### Phase 2: Consolidation (4-6 weeks)

**Week 4-5:**
- [x] Create WorkspaceService abstraction
- [x] Refactor workspace services
- [x] Create custom exception hierarchy
- [x] Update all routers

**Week 6-7:**
- [x] Implement API versioning
- [x] Add deprecation middleware
- [x] Update frontend API client
- [x] Document API versions

**Week 8-9:**
- [ ] Refactor large backend files
- [ ] Split prompts into templates
- [ ] Add integration tests

### Phase 3: Modernization (6-8 weeks)

**Week 10-12:**
- [x] Add Prometheus metrics
- [x] Implement Sentry error tracking
- [ ] Create dashboards

**Week 16:**
- [ ] Final testing
- [ ] Documentation updates
- [ ] Deployment

---

## Rollback Procedures

### Component Refactoring Rollback

```bash
# If component refactor fails
git revert <commit-hash>
npm run build
npm run test
```

### API Versioning Rollback

```python
# Remove versioned routes, keep legacy only
# backend/api/main.py
app.include_router(chat.router, prefix="/api/chat", tags=["chat"])
# Remove /api/v1/ routes
```

### Database Migration Rollback

```bash
# Rollback database migration
alembic downgrade -1

# Restore from backup if needed
pg_restore -d sidebar backups/sidebar_backup.dump
```

---

## Monitoring & Success Metrics

### Performance Metrics

- **Chat streaming latency**: < 500ms to first token
- **API response time**: p95 < 200ms
- **Frontend load time**: < 2 seconds
- **Test execution time**: < 5 minutes

### Quality Metrics

- **Backend test coverage**: > 90%
- **Frontend test coverage**: > 70%
- **Code duplication**: < 5%
- **Component size**: Average < 300 LOC

### Reliability Metrics

- **Error rate**: < 0.1%
- **Uptime**: > 99.9%
- **Failed deployments**: 0

---

## Documentation Updates Required

- [ ] Update README with new architecture
- [x] Document API versioning strategy
- [ ] Update deployment guide
- [ ] Create migration guide for API consumers
- [x] Document new error codes
- [ ] Update contributing guide with new patterns
- [ ] Create refactoring ADRs (Architecture Decision Records)

---

## Next Steps

1. **Review this plan** with team/stakeholders
2. **Prioritize phases** based on business needs
3. **Set up tracking** (GitHub project, Jira, etc.)
4. **Begin Phase 1** with frontend testing
5. **Monitor progress** weekly
6. **Adjust timeline** as needed

---

## Questions for Decision

Before starting refactoring, answer these questions:

1. **Are you planning to scale beyond single-user?**
   - Yes → Prioritize Redis + horizontal scaling
   - No → Defer Phase 3

2. **Do you have regression bugs?**
   - Yes → Prioritize frontend testing immediately
   - No → Can defer some testing

3. **Are new features getting harder to add?**
   - Yes → Prioritize component decomposition
   - No → Lower priority

4. **Do you need mobile clients?**
   - Yes → Prioritize API versioning
   - No → Can defer

5. **Are you hitting performance limits?**
   - Yes → Add observability first to measure
   - No → Defer Phase 3

---

**Document Version**: 1.0
**Last Updated**: 2026-01-04
**Next Review**: After Phase 1 completion
