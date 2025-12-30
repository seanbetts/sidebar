# localStorage Optimization Plan

## Goal

Improve frontend responsiveness and perceived performance by intelligently caching API responses and application state in localStorage, while maintaining data consistency and implementing proper cache invalidation strategies.

**Target Impact**:
- Instant sidebar section population on repeat visits
- Preserve user context across sessions (last conversation, expanded folders)
- Reduce API load by 40-60% for repeat actions
- Zero perceived latency for cached UI components

---

## Current State Analysis

### What's Already Cached ✓

1. **Layout State** (`src/lib/stores/layout.ts`)
   - Key: `sideBar.layout`
   - Data: `{ mode: 'default' | 'chat-focused', sidebarRatio: number }`
   - Pattern: Persisted on every change, loaded on app init
   - Migration: Handles legacy keys gracefully

2. **Theme Preference** (`src/lib/utils/theme.ts`)
   - Key: `theme`
   - Data: `"light"` | `"dark"`
   - Pattern: Explicit persistence via `setThemeMode()`
   - Event: Dispatches `themechange` custom event

3. **Weather & Location** (`src/lib/hooks/useSiteHeaderData.ts`)
   - Keys with TTL:
     - `sidebar.liveLocation` + `sidebar.liveLocationTs` (30 min)
     - `sidebar.liveLocationLevels` (location hierarchy)
     - `sidebar.coords` + `sidebar.coordsTs` (24 hours)
     - `sidebar.weather` + `sidebar.weatherTs` (30 min)
   - Pattern: TTL-based expiration, falls back to API

### What's NOT Cached (Opportunities)

**High-Impact Data**:
- Conversation list (loaded fresh on every 'history' section access)
- Websites list (loaded fresh on every 'websites' section access)
- Last active conversation ID (lost on page refresh)
- File tree expansion state (folders collapse on refresh)
- Notes tree structure (loaded fresh every time)

**Medium-Impact Data**:
- User settings/preferences
- Recent chat messages (last N per conversation)
- Memory/skills metadata

**Current Load Pattern**:
```
User clicks section → Check store.loaded flag →
If false → API call → Update store → Set loaded = true
```

**Problem**: `loaded` flag is in-memory only - resets on page refresh.

---

## Architecture & Patterns

### Cache Strategy Pattern

Use a **tiered caching approach**:

```typescript
// Tier 1: Memory (Svelte stores) - fastest
// Tier 2: localStorage - fast, persistent
// Tier 3: API - authoritative source

async function loadData<T>(
  cacheKey: string,
  apiFetcher: () => Promise<T>,
  options: {
    ttl?: number;           // Time-to-live in milliseconds
    staleWhileRevalidate?: boolean;  // Use stale data while fetching
    version?: string;       // Cache version for invalidation
  }
): Promise<T> {
  // 1. Check memory (Svelte store)
  if (memoryCache.has(cacheKey)) {
    return memoryCache.get(cacheKey);
  }

  // 2. Check localStorage
  const cached = getCachedData<T>(cacheKey, options.ttl);
  if (cached) {
    memoryCache.set(cacheKey, cached);

    // If stale-while-revalidate, fetch fresh in background
    if (options.staleWhileRevalidate && isCacheStale(cacheKey, options.ttl)) {
      revalidateInBackground(cacheKey, apiFetcher);
    }

    return cached;
  }

  // 3. Fetch from API
  const fresh = await apiFetcher();
  setCachedData(cacheKey, fresh, options.version);
  memoryCache.set(cacheKey, fresh);
  return fresh;
}
```

### Cache Invalidation Strategy

**Invalidation Triggers**:
1. **Mutation Events**: Clear cache when data changes
2. **TTL Expiration**: Time-based expiration
3. **Version Mismatch**: Detect schema changes
4. **Manual Clear**: User logout, settings reset

**Implementation**:
```typescript
// Cache metadata structure
interface CacheMetadata {
  data: unknown;
  timestamp: number;
  version: string;
  ttl: number;
}

// Invalidation registry
const invalidationMap = {
  'conversations.list': ['conversation.created', 'conversation.deleted', 'conversation.title_updated'],
  'websites.list': ['website.saved', 'website.deleted'],
  'notes.tree': ['note.created', 'note.deleted', 'note.moved'],
  'files.tree': ['file.uploaded', 'file.deleted', 'file.moved']
};
```

---

## Implementation Phases

### Phase 1: Core Cache Utilities (2 hours)

Create reusable caching infrastructure.

#### 1.1 Cache Manager Utility

**New file**: `/frontend/src/lib/utils/cache.ts`

```typescript
/**
 * Cache configuration
 */
export interface CacheConfig {
  ttl?: number;                    // Time-to-live in milliseconds
  version?: string;                // Cache version for invalidation
  staleWhileRevalidate?: boolean;  // Use stale data while fetching fresh
}

/**
 * Cache metadata stored alongside data
 */
interface CacheMetadata<T> {
  data: T;
  timestamp: number;
  version: string;
  ttl: number;
}

/**
 * Cache key prefix for namespacing
 */
const CACHE_PREFIX = 'sideBar.cache.';

/**
 * Default TTL: 15 minutes
 */
const DEFAULT_TTL = 15 * 60 * 1000;

/**
 * Get cached data if valid
 */
export function getCachedData<T>(
  key: string,
  ttl: number = DEFAULT_TTL
): T | null {
  try {
    const raw = localStorage.getItem(CACHE_PREFIX + key);
    if (!raw) return null;

    const metadata: CacheMetadata<T> = JSON.parse(raw);
    const age = Date.now() - metadata.timestamp;

    // Check TTL
    if (age > (metadata.ttl || ttl)) {
      localStorage.removeItem(CACHE_PREFIX + key);
      return null;
    }

    return metadata.data;
  } catch (error) {
    console.error(`Cache read error for ${key}:`, error);
    return null;
  }
}

/**
 * Set cached data with metadata
 */
export function setCachedData<T>(
  key: string,
  data: T,
  config: CacheConfig = {}
): void {
  try {
    const metadata: CacheMetadata<T> = {
      data,
      timestamp: Date.now(),
      version: config.version || '1.0',
      ttl: config.ttl || DEFAULT_TTL
    };

    localStorage.setItem(
      CACHE_PREFIX + key,
      JSON.stringify(metadata)
    );
  } catch (error) {
    console.error(`Cache write error for ${key}:`, error);
    // Handle quota exceeded
    if (error instanceof DOMException && error.name === 'QuotaExceededError') {
      clearOldestCaches();
    }
  }
}

/**
 * Check if cache is stale (for stale-while-revalidate)
 */
export function isCacheStale(
  key: string,
  maxAge: number = DEFAULT_TTL
): boolean {
  try {
    const raw = localStorage.getItem(CACHE_PREFIX + key);
    if (!raw) return true;

    const metadata: CacheMetadata<unknown> = JSON.parse(raw);
    const age = Date.now() - metadata.timestamp;

    return age > (metadata.ttl || maxAge) * 0.8; // 80% of TTL
  } catch {
    return true;
  }
}

/**
 * Invalidate specific cache key
 */
export function invalidateCache(key: string): void {
  localStorage.removeItem(CACHE_PREFIX + key);
}

/**
 * Invalidate multiple cache keys
 */
export function invalidateCaches(keys: string[]): void {
  keys.forEach(invalidateCache);
}

/**
 * Clear all caches with optional pattern matching
 */
export function clearCaches(pattern?: RegExp): void {
  const keys = Object.keys(localStorage);
  keys.forEach(key => {
    if (key.startsWith(CACHE_PREFIX)) {
      if (!pattern || pattern.test(key)) {
        localStorage.removeItem(key);
      }
    }
  });
}

/**
 * Clear oldest caches to free up space
 */
function clearOldestCaches(): void {
  const caches: Array<{ key: string; timestamp: number }> = [];

  Object.keys(localStorage).forEach(key => {
    if (key.startsWith(CACHE_PREFIX)) {
      try {
        const metadata = JSON.parse(localStorage.getItem(key) || '{}');
        caches.push({ key, timestamp: metadata.timestamp || 0 });
      } catch {
        // Invalid cache entry, remove it
        localStorage.removeItem(key);
      }
    }
  });

  // Sort by age and remove oldest 25%
  caches.sort((a, b) => a.timestamp - b.timestamp);
  const toRemove = Math.ceil(caches.length * 0.25);
  caches.slice(0, toRemove).forEach(({ key }) => {
    localStorage.removeItem(key);
  });
}

/**
 * Get cache statistics
 */
export function getCacheStats(): {
  count: number;
  totalSize: number;
  oldestAge: number;
} {
  let count = 0;
  let totalSize = 0;
  let oldestTimestamp = Date.now();

  Object.keys(localStorage).forEach(key => {
    if (key.startsWith(CACHE_PREFIX)) {
      count++;
      const value = localStorage.getItem(key) || '';
      totalSize += new Blob([value]).size;

      try {
        const metadata = JSON.parse(value);
        if (metadata.timestamp < oldestTimestamp) {
          oldestTimestamp = metadata.timestamp;
        }
      } catch {}
    }
  });

  return {
    count,
    totalSize,
    oldestAge: Date.now() - oldestTimestamp
  };
}
```

#### 1.2 Cache Event System

**New file**: `/frontend/src/lib/utils/cacheEvents.ts`

```typescript
/**
 * Cache invalidation event system
 */

type CacheEventType =
  | 'conversation.created'
  | 'conversation.deleted'
  | 'conversation.updated'
  | 'website.saved'
  | 'website.deleted'
  | 'note.created'
  | 'note.deleted'
  | 'note.updated'
  | 'note.moved'
  | 'file.uploaded'
  | 'file.deleted'
  | 'memory.created'
  | 'memory.updated'
  | 'memory.deleted'
  | 'user.logout';

/**
 * Mapping of events to cache keys they should invalidate
 */
const INVALIDATION_MAP: Record<CacheEventType, string[]> = {
  'conversation.created': ['conversations.list'],
  'conversation.deleted': ['conversations.list'],
  'conversation.updated': ['conversations.list'],
  'website.saved': ['websites.list'],
  'website.deleted': ['websites.list'],
  'note.created': ['notes.tree', 'files.notes'],
  'note.deleted': ['notes.tree', 'files.notes'],
  'note.updated': ['notes.tree', 'files.notes'],
  'note.moved': ['notes.tree', 'files.notes'],
  'file.uploaded': ['files.tree', 'files.workspace'],
  'file.deleted': ['files.tree', 'files.workspace'],
  'memory.created': ['memories.list'],
  'memory.updated': ['memories.list'],
  'memory.deleted': ['memories.list'],
  'user.logout': ['*'] // Clear all caches
};

/**
 * Dispatch cache invalidation event
 */
export function dispatchCacheEvent(eventType: CacheEventType): void {
  const cacheKeys = INVALIDATION_MAP[eventType] || [];

  if (cacheKeys.includes('*')) {
    // Clear all caches
    import('./cache').then(({ clearCaches }) => clearCaches());
  } else {
    // Invalidate specific caches
    import('./cache').then(({ invalidateCaches }) => invalidateCaches(cacheKeys));
  }

  // Also dispatch custom event for listeners
  window.dispatchEvent(new CustomEvent('cache:invalidate', {
    detail: { eventType, cacheKeys }
  }));
}

/**
 * Listen for cache invalidation events
 */
export function onCacheInvalidate(
  callback: (detail: { eventType: CacheEventType; cacheKeys: string[] }) => void
): () => void {
  const handler = ((event: CustomEvent) => {
    callback(event.detail);
  }) as EventListener;

  window.addEventListener('cache:invalidate', handler);

  // Return cleanup function
  return () => window.removeEventListener('cache:invalidate', handler);
}
```

---

### Phase 2: Conversation List Caching (1.5 hours)

**Highest impact optimization** - makes history section instantly responsive.

#### 2.1 Update Conversation List Store

**File**: `/frontend/src/lib/stores/conversations.ts`

**Add caching layer**:

```typescript
import { writable, get } from 'svelte/store';
import { getCachedData, setCachedData, isCacheStale, invalidateCache } from '$lib/utils/cache';
import type { Conversation } from '$lib/types';

const CACHE_KEY = 'conversations.list';
const CACHE_TTL = 10 * 60 * 1000; // 10 minutes

interface ConversationListState {
  conversations: Conversation[];
  loaded: boolean;
  loading: boolean;
}

function createConversationListStore() {
  const { subscribe, set, update } = writable<ConversationListState>({
    conversations: [],
    loaded: false,
    loading: false
  });

  return {
    subscribe,

    async load(forceRefresh = false) {
      const state = get({ subscribe });

      // Return if already loaded and not forcing refresh
      if (state.loaded && !forceRefresh) {
        return;
      }

      // Return if already loading
      if (state.loading) {
        return;
      }

      update(s => ({ ...s, loading: true }));

      try {
        // Try cache first (unless forcing refresh)
        if (!forceRefresh) {
          const cached = getCachedData<Conversation[]>(CACHE_KEY, CACHE_TTL);
          if (cached) {
            set({ conversations: cached, loaded: true, loading: false });

            // Revalidate in background if stale
            if (isCacheStale(CACHE_KEY, CACHE_TTL)) {
              this.revalidateInBackground();
            }

            return;
          }
        }

        // Fetch from API
        const response = await fetch('/api/conversations');
        if (!response.ok) throw new Error('Failed to load conversations');

        const conversations = await response.json();

        // Update cache and store
        setCachedData(CACHE_KEY, conversations, { ttl: CACHE_TTL });
        set({ conversations, loaded: true, loading: false });
      } catch (error) {
        console.error('Failed to load conversations:', error);
        update(s => ({ ...s, loading: false }));
        throw error;
      }
    },

    async revalidateInBackground() {
      try {
        const response = await fetch('/api/conversations');
        if (!response.ok) return;

        const conversations = await response.json();
        setCachedData(CACHE_KEY, conversations, { ttl: CACHE_TTL });
        update(s => ({ ...s, conversations }));
      } catch (error) {
        console.error('Background revalidation failed:', error);
      }
    },

    invalidateCache() {
      invalidateCache(CACHE_KEY);
      update(s => ({ ...s, loaded: false }));
    },

    reset() {
      set({ conversations: [], loaded: false, loading: false });
      invalidateCache(CACHE_KEY);
    }
  };
}

export const conversationListStore = createConversationListStore();
```

#### 2.2 Wire Up Cache Invalidation

**In conversation mutation handlers**, add cache invalidation:

```typescript
import { dispatchCacheEvent } from '$lib/utils/cacheEvents';

// After creating a conversation
async function createConversation() {
  const response = await fetch('/api/conversations', { method: 'POST' });
  const conversation = await response.json();

  // Invalidate cache
  dispatchCacheEvent('conversation.created');

  return conversation;
}

// After deleting a conversation
async function deleteConversation(id: string) {
  await fetch(`/api/conversations/${id}`, { method: 'DELETE' });

  // Invalidate cache
  dispatchCacheEvent('conversation.deleted');
}

// After SSE stream completes (conversation updated)
onComplete: async () => {
  await chatStore.finishStreaming(assistantMessageId);

  // Invalidate cache (new message = updated timestamp)
  dispatchCacheEvent('conversation.updated');
}
```

---

### Phase 3: Last Active Conversation Persistence (1 hour)

Restore user's last conversation on page load.

#### 3.1 Update Chat Store

**File**: `/frontend/src/lib/stores/chat.ts`

```typescript
const LAST_CONVERSATION_KEY = 'sideBar.lastConversation';

function createChatStore() {
  // ... existing code ...

  return {
    subscribe,

    async loadConversation(conversationId: string) {
      // ... existing load logic ...

      // Persist last conversation
      try {
        localStorage.setItem(LAST_CONVERSATION_KEY, conversationId);
      } catch (error) {
        console.warn('Failed to persist last conversation:', error);
      }
    },

    getLastConversationId(): string | null {
      try {
        return localStorage.getItem(LAST_CONVERSATION_KEY);
      } catch {
        return null;
      }
    },

    clearLastConversation() {
      try {
        localStorage.removeItem(LAST_CONVERSATION_KEY);
      } catch {}
    },

    reset() {
      set(createInitialState());
      this.clearLastConversation();
    }
  };
}
```

#### 3.2 Auto-Restore on App Load

**File**: `/frontend/src/routes/(authenticated)/+layout.svelte`

```typescript
import { chatStore } from '$lib/stores/chat';
import { onMount } from 'svelte';
import { get } from 'svelte/store';

onMount(async () => {
  // ... existing onMount code ...

  // Auto-restore last conversation if none active
  const currentState = get(chatStore);
  if (!currentState.conversationId) {
    const lastConversationId = chatStore.getLastConversationId();
    if (lastConversationId) {
      try {
        await chatStore.loadConversation(lastConversationId);
      } catch (error) {
        // Conversation may have been deleted
        console.warn('Failed to restore last conversation:', error);
        chatStore.clearLastConversation();
      }
    }
  }
});
```

---

### Phase 4: Websites List Caching (0.5 hours)

Same pattern as conversations.

#### 4.1 Update Websites Store

**File**: `/frontend/src/lib/stores/websites.ts`

```typescript
import { getCachedData, setCachedData, invalidateCache, isCacheStale } from '$lib/utils/cache';
import type { Website } from '$lib/types';

const CACHE_KEY = 'websites.list';
const CACHE_TTL = 15 * 60 * 1000; // 15 minutes

async load(forceRefresh = false) {
  if (this.loaded && !forceRefresh) return;

  // Try cache
  if (!forceRefresh) {
    const cached = getCachedData<Website[]>(CACHE_KEY, CACHE_TTL);
    if (cached) {
      set({ items: cached, loaded: true, active: get(this).active });

      // Revalidate in background if stale
      if (isCacheStale(CACHE_KEY, CACHE_TTL)) {
        this.revalidateInBackground();
      }

      return;
    }
  }

  // Fetch from API
  const response = await fetch('/api/websites');
  const items = await response.json();

  setCachedData(CACHE_KEY, items, { ttl: CACHE_TTL });
  update(s => ({ ...s, items, loaded: true }));
}

async revalidateInBackground() {
  try {
    const response = await fetch('/api/websites');
    if (!response.ok) return;

    const items = await response.json();
    setCachedData(CACHE_KEY, items, { ttl: CACHE_TTL });
    update(s => ({ ...s, items }));
  } catch (error) {
    console.error('Background revalidation failed:', error);
  }
}
```

#### 4.2 Wire Up Invalidation

**In SSE handlers** where websites are saved/deleted:

```typescript
import { dispatchCacheEvent } from '$lib/utils/cacheEvents';

onWebsiteSaved: async () => {
  await websitesStore.load(true); // Force refresh
  dispatchCacheEvent('website.saved');
},

onWebsiteDeleted: async () => {
  await websitesStore.load(true); // Force refresh
  dispatchCacheEvent('website.deleted');
}
```

---

### Phase 5: File Tree Expansion State (2 hours)

Persist which folders are expanded.

#### 5.1 Update Files Component

**File**: `/frontend/src/lib/components/workspace/FilesSection.svelte`

```typescript
import { onMount } from 'svelte';

const EXPANDED_PATHS_KEY = 'sideBar.expandedPaths';

let expandedPaths = $state<Set<string>>(new Set());

// Load persisted expansion state
onMount(() => {
  try {
    const stored = localStorage.getItem(EXPANDED_PATHS_KEY);
    if (stored) {
      expandedPaths = new Set(JSON.parse(stored));
    }
  } catch (error) {
    console.error('Failed to load expanded paths:', error);
  }
});

// Persist changes
function toggleFolder(path: string) {
  if (expandedPaths.has(path)) {
    expandedPaths.delete(path);
  } else {
    expandedPaths.add(path);
  }

  // Trigger reactivity
  expandedPaths = new Set(expandedPaths);

  // Persist
  try {
    localStorage.setItem(
      EXPANDED_PATHS_KEY,
      JSON.stringify([...expandedPaths])
    );
  } catch (error) {
    console.error('Failed to persist expanded paths:', error);
  }
}
```

---

### Phase 6: Notes Tree Caching (1 hour)

Cache the file tree structure.

#### 6.1 Update Files Store

**File**: `/frontend/src/lib/stores/files.ts`

```typescript
import { getCachedData, setCachedData, isCacheStale } from '$lib/utils/cache';

const NOTES_TREE_CACHE_KEY = 'notes.tree';
const WORKSPACE_TREE_CACHE_KEY = 'files.tree';
const TREE_CACHE_TTL = 30 * 60 * 1000; // 30 minutes

async load(section: 'notes' | 'workspace', forceRefresh = false) {
  const cacheKey = section === 'notes' ? NOTES_TREE_CACHE_KEY : WORKSPACE_TREE_CACHE_KEY;

  if (!forceRefresh) {
    const cached = getCachedData<FileNode[]>(cacheKey, TREE_CACHE_TTL);
    if (cached) {
      update(s => {
        s.trees[section] = { children: cached, loaded: true };
        return s;
      });

      // Revalidate in background if stale
      if (isCacheStale(cacheKey, TREE_CACHE_TTL)) {
        this.revalidateInBackground(section);
      }

      return;
    }
  }

  // Fetch from API
  const endpoint = section === 'notes' ? '/api/notes/tree' : '/api/files';
  const response = await fetch(endpoint);
  const tree = await response.json();

  setCachedData(cacheKey, tree, { ttl: TREE_CACHE_TTL });
  update(s => {
    s.trees[section] = { children: tree, loaded: true };
    return s;
  });
}

async revalidateInBackground(section: 'notes' | 'workspace') {
  try {
    const endpoint = section === 'notes' ? '/api/notes/tree' : '/api/files';
    const response = await fetch(endpoint);
    if (!response.ok) return;

    const tree = await response.json();
    const cacheKey = section === 'notes' ? NOTES_TREE_CACHE_KEY : WORKSPACE_TREE_CACHE_KEY;

    setCachedData(cacheKey, tree, { ttl: TREE_CACHE_TTL });
    update(s => {
      s.trees[section] = { children: tree, loaded: true };
      return s;
    });
  } catch (error) {
    console.error('Background revalidation failed:', error);
  }
}
```

---

### Phase 7: Stale-While-Revalidate for Weather (1 hour)

Improve weather caching to use stale data while fetching fresh.

#### 7.1 Update Site Header Hook

**File**: `/frontend/src/lib/hooks/useSiteHeaderData.ts`

```typescript
async function fetchWeather(coords: GeolocationCoordinates) {
  const cacheKey = 'sidebar.weather';
  const cacheTsKey = 'sidebar.weatherTs';
  const WEATHER_TTL = 30 * 60 * 1000; // 30 minutes

  // Check cache
  const cachedTs = localStorage.getItem(cacheTsKey);
  const cachedData = localStorage.getItem(cacheKey);

  if (cachedTs && cachedData) {
    const age = Date.now() - parseInt(cachedTs, 10);

    // Return cached data immediately
    const cached = JSON.parse(cachedData);

    // If stale (>80% of TTL), revalidate in background
    if (age > WEATHER_TTL * 0.8) {
      // Don't await - fetch in background
      revalidateWeather(coords).catch(console.error);
    }

    // Only reject cache if fully expired
    if (age < WEATHER_TTL) {
      return cached;
    }
  }

  // No valid cache - fetch synchronously
  return revalidateWeather(coords);
}

async function revalidateWeather(coords: GeolocationCoordinates) {
  const response = await fetch(
    `/api/weather?lat=${coords.latitude}&lon=${coords.longitude}`
  );
  const data = await response.json();

  // Update cache
  localStorage.setItem('sidebar.weather', JSON.stringify(data));
  localStorage.setItem('sidebar.weatherTs', Date.now().toString());

  return data;
}
```

---

### Phase 8: Global Cache Cleanup (0.5 hours)

Add cleanup on logout and settings.

#### 8.1 Logout Handler

**File**: `/frontend/src/lib/components/auth/LogoutButton.svelte` (or wherever logout is handled)

```typescript
import { clearCaches } from '$lib/utils/cache';
import { dispatchCacheEvent } from '$lib/utils/cacheEvents';

async function handleLogout() {
  // Sign out from Supabase
  await supabase.auth.signOut();

  // Clear all caches
  clearCaches();

  // Dispatch logout event
  dispatchCacheEvent('user.logout');

  // Redirect to login
  await goto('/auth/login');
}
```

#### 8.2 Add Cache Management to Settings

**File**: `/frontend/src/lib/components/settings/SettingsDialog.svelte`

Add a "Storage & Cache" section:

```svelte
<script lang="ts">
  import { getCacheStats, clearCaches } from '$lib/utils/cache';
  import { Button } from '$lib/components/ui/button';
  import { onMount } from 'svelte';

  let cacheStats = $state({ count: 0, totalSize: 0, oldestAge: 0 });

  function loadCacheStats() {
    cacheStats = getCacheStats();
  }

  function handleClearCache() {
    if (confirm('Are you sure you want to clear all cached data?')) {
      clearCaches();
      loadCacheStats();
      // Show success message (toast or similar)
      console.log('Cache cleared successfully');
    }
  }

  onMount(loadCacheStats);
</script>

<section class="settings-section">
  <h3>Storage & Cache</h3>

  <div class="cache-stats">
    <p>Cached items: <strong>{cacheStats.count}</strong></p>
    <p>Cache size: <strong>{(cacheStats.totalSize / 1024).toFixed(2)} KB</strong></p>
    <p>Oldest cache: <strong>{(cacheStats.oldestAge / 1000 / 60).toFixed(0)} minutes ago</strong></p>
  </div>

  <Button variant="destructive" onclick={handleClearCache}>
    Clear All Caches
  </Button>
</section>

<style>
  .settings-section {
    padding: 1.5rem;
    border-bottom: 1px solid var(--color-border);
  }

  .cache-stats {
    margin: 1rem 0;
    padding: 1rem;
    background: var(--color-muted);
    border-radius: 0.5rem;
  }

  .cache-stats p {
    margin: 0.5rem 0;
  }
</style>
```

---

## Testing Checklist

### Unit Tests

- [ ] Cache utility functions (`getCachedData`, `setCachedData`)
- [ ] TTL expiration logic
- [ ] Cache invalidation
- [ ] Quota exceeded handling (storage full)
- [ ] Version mismatch detection

### Integration Tests

- [ ] Conversation list caching:
  - [ ] First load fetches from API
  - [ ] Second load returns cached data
  - [ ] Cache invalidates on new message
  - [ ] Cache invalidates on conversation deletion
- [ ] Websites list caching:
  - [ ] Cache persists across page refreshes
  - [ ] Invalidates on website saved/deleted
- [ ] Last conversation persistence:
  - [ ] Restores on page load
  - [ ] Clears on logout
- [ ] File tree expansion:
  - [ ] State persists across refreshes
  - [ ] Handles deeply nested paths
- [ ] Stale-while-revalidate:
  - [ ] Returns stale data immediately
  - [ ] Revalidates in background
  - [ ] Updates UI after revalidation

### Performance Tests

- [ ] Measure API calls before/after caching (should reduce by 40-60%)
- [ ] Measure perceived load time for sidebar sections
- [ ] Test with localStorage quota exceeded
- [ ] Test with large datasets (1000+ conversations)
- [ ] Verify no memory leaks from cache listeners

### User Experience Tests

- [ ] Navigate to history → instant population
- [ ] Refresh page → last conversation restored
- [ ] Create new conversation → cache invalidates
- [ ] Delete website → cache invalidates
- [ ] Expand folders → state persists
- [ ] Logout → all caches cleared

---

## Performance Metrics

### Before Optimization (Baseline)

| Action | Time | API Calls |
|--------|------|-----------|
| First load (history section) | 200-500ms | 1 |
| Repeat load (same session) | 0ms (in-memory) | 0 |
| Repeat load (after refresh) | 200-500ms | 1 |
| Switch sections | 200-500ms each | 1 each |

### After Optimization (Target)

| Action | Time | API Calls |
|--------|------|-----------|
| First load (history section) | 200-500ms | 1 |
| Repeat load (same session) | 0ms (memory) | 0 |
| Repeat load (after refresh) | <10ms (localStorage) | 0 |
| Switch sections | <10ms (cached) | 0 (first 10 min) |

**Target Improvements**:
- 95%+ reduction in repeat API calls
- <10ms perceived latency for cached sections
- 40-60% reduction in total API load
- Zero data loss on page refresh (context preserved)

---

## Migration & Rollout

### Development

1. Implement cache utilities (Phase 1)
2. Add unit tests for cache functions
3. Implement conversation list caching (Phase 2)
4. Test thoroughly in dev environment
5. Iterate through remaining phases

### Staging

1. Deploy with cache enabled
2. Monitor localStorage usage
3. Test quota exceeded scenarios
4. Verify cache invalidation works correctly
5. Check for memory leaks

### Production

1. Enable caching for all users
2. Monitor API load reduction
3. Track localStorage quota errors
4. Gather user feedback on responsiveness
5. Fine-tune TTL values based on usage patterns

### Rollback Plan

If issues occur:
1. All caching is **additive** - can be disabled via feature flag
2. App continues to work without caching (falls back to API)
3. Clear all user caches via settings UI
4. Investigate and fix issues
5. Re-enable when ready

---

## Success Criteria

- [ ] Conversation list loads instantly on repeat visits (<10ms)
- [ ] Websites list loads instantly on repeat visits (<10ms)
- [ ] Last conversation restored on page refresh
- [ ] File tree expansion state persists across sessions
- [ ] API call volume reduced by 40-60% for repeat actions
- [ ] No localStorage quota errors for typical usage
- [ ] Cache invalidation works correctly on all mutations
- [ ] Zero regressions in data consistency
- [ ] Smooth user experience with stale-while-revalidate

---

## Estimated Effort

| Phase | Description | Time |
|-------|-------------|------|
| 1 | Core cache utilities | 2 hours |
| 2 | Conversation list caching | 1.5 hours |
| 3 | Last conversation persistence | 1 hour |
| 4 | Websites list caching | 0.5 hours |
| 5 | File tree expansion state | 2 hours |
| 6 | Notes tree caching | 1 hour |
| 7 | Stale-while-revalidate weather | 1 hour |
| 8 | Global cache cleanup | 0.5 hours |
| **Testing** | Unit + integration tests | 2 hours |
| **Documentation** | Update docs | 0.5 hours |

**Total**: ~12 hours

---

## Future Enhancements

### Phase 9: IndexedDB for Large Datasets (4+ hours)

For storing chat message history, file content, etc.

**Benefits**:
- 50MB+ storage vs localStorage's 5-10MB
- Structured queries
- Better performance for large datasets
- Full-text search capability

**Libraries**:
- `idb` (Promise-based IndexedDB wrapper)
- `dexie` (Full-featured IndexedDB library)

### Phase 10: Service Worker Caching (6+ hours)

For offline-first architecture.

**Benefits**:
- True offline support
- Background sync
- Push notifications
- Network-first/cache-first strategies

### Phase 11: Request Deduplication (2 hours)

Prevent multiple identical API calls in flight.

**Pattern**:
```typescript
const inFlightRequests = new Map<string, Promise<any>>();

async function fetchWithDeduplication(url: string) {
  if (inFlightRequests.has(url)) {
    return inFlightRequests.get(url);
  }

  const promise = fetch(url).then(r => r.json());
  inFlightRequests.set(url, promise);

  try {
    const result = await promise;
    return result;
  } finally {
    inFlightRequests.delete(url);
  }
}
```

---

## Notes

- All caching is **additive** - won't break existing functionality
- TTL values can be tuned based on usage patterns
- Cache versioning allows for safe schema updates
- Quota handling prevents storage overflow
- Event-driven invalidation keeps data fresh
- Stale-while-revalidate provides best UX
- Each phase can be implemented and tested independently
- Start with Phase 2 (conversations) for highest impact
