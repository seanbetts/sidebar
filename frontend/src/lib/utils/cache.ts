import { browser } from '$app/environment';
import { get } from 'svelte/store';
import { user } from '$lib/stores/auth';

export interface CacheConfig {
  ttl?: number;
  version?: string;
  staleWhileRevalidate?: boolean;
}

interface CacheMetadata<T> {
  data: T;
  timestamp: number;
  version: string;
  globalVersion?: string;
  ttl: number;
}

const CACHE_PREFIX = (userId: string) => `sideBar.cache.${userId}.`;
const DEFAULT_TTL = 15 * 60 * 1000;
const GLOBAL_CACHE_VERSION = '1';
const MAX_MEMORY_ENTRIES = 100;
const REVALIDATE_DEBOUNCE_MS = 5000;
const CACHE_ENABLED = import.meta.env.VITE_ENABLE_CACHE !== 'false';

const memoryCache = new Map<string, unknown>();
const memoryKeys: string[] = [];
const inFlightRequests = new Map<string, Promise<unknown>>();
const revalidateAt = new Map<string, number>();

function hasStorage(): boolean {
  if (!browser) return false;
  try {
    const testKey = '__sidebar_cache_test__';
    localStorage.setItem(testKey, '1');
    localStorage.removeItem(testKey);
    return true;
  } catch {
    return false;
  }
}

function isCacheEnabled(): boolean {
  return CACHE_ENABLED && hasStorage();
}

function getActiveUserId(): string {
  const currentUser = get(user);
  return currentUser?.id ?? 'anonymous';
}

function buildKey(cacheKey: string): string {
  return `${CACHE_PREFIX(getActiveUserId())}${cacheKey}`;
}

function touch(key: string): void {
  const index = memoryKeys.indexOf(key);
  if (index >= 0) {
    memoryKeys.splice(index, 1);
  }
  memoryKeys.push(key);
}

function remember(key: string, value: unknown): void {
  if (memoryCache.has(key)) {
    touch(key);
    memoryCache.set(key, value);
    return;
  }
  memoryCache.set(key, value);
  memoryKeys.push(key);
  if (memoryKeys.length > MAX_MEMORY_ENTRIES) {
    const oldest = memoryKeys.shift();
    if (oldest) {
      memoryCache.delete(oldest);
    }
  }
}

export function getCachedData<T>(key: string, config: CacheConfig = {}): T | null {
  if (!isCacheEnabled()) return null;

  if (memoryCache.has(key)) {
    touch(key);
    return memoryCache.get(key) as T;
  }

  try {
    const ttl = config.ttl ?? DEFAULT_TTL;
    const version = config.version ?? '1.0';
    const raw = localStorage.getItem(buildKey(key));
    if (!raw) return null;

    const metadata: CacheMetadata<T> = JSON.parse(raw);
    const age = Date.now() - metadata.timestamp;

    if (metadata.version && metadata.version !== version) {
      localStorage.removeItem(buildKey(key));
      return null;
    }

    if (metadata.globalVersion && metadata.globalVersion !== GLOBAL_CACHE_VERSION) {
      localStorage.removeItem(buildKey(key));
      return null;
    }

    if (age > (metadata.ttl || ttl)) {
      localStorage.removeItem(buildKey(key));
      return null;
    }

    remember(key, metadata.data);
    return metadata.data;
  } catch (error) {
    console.error(`Cache read error for ${key}:`, error);
    return null;
  }
}

export function setCachedData<T>(key: string, data: T, config: CacheConfig = {}): void {
  if (!isCacheEnabled()) return;

  const metadata: CacheMetadata<T> = {
    data,
    timestamp: Date.now(),
    version: config.version || '1.0',
    globalVersion: GLOBAL_CACHE_VERSION,
    ttl: config.ttl || DEFAULT_TTL
  };

  try {
    localStorage.setItem(buildKey(key), JSON.stringify(metadata));
    remember(key, data);
  } catch (error) {
    console.error(`Cache write error for ${key}:`, error);
    if (error instanceof DOMException && error.name === 'QuotaExceededError') {
      clearOldestCaches();
      try {
        localStorage.setItem(buildKey(key), JSON.stringify(metadata));
        remember(key, data);
      } catch (retryError) {
        console.error(`Cache retry failed for ${key}:`, retryError);
      }
    }
  }
}

export function isCacheStale(key: string, maxAge: number = DEFAULT_TTL): boolean {
  if (!isCacheEnabled()) return true;
  try {
    const raw = localStorage.getItem(buildKey(key));
    if (!raw) return true;

    const metadata: CacheMetadata<unknown> = JSON.parse(raw);
    const age = Date.now() - metadata.timestamp;

    return age > (metadata.ttl || maxAge) * 0.8;
  } catch {
    return true;
  }
}

export function invalidateCache(key: string): void {
  if (!isCacheEnabled()) return;
  localStorage.removeItem(buildKey(key));
  clearMemoryCache([key]);
}

export function invalidateCaches(keys: string[]): void {
  keys.forEach(invalidateCache);
}

export function clearCaches(pattern?: RegExp): void {
  if (!isCacheEnabled()) return;
  const keys = Object.keys(localStorage);
  const prefix = CACHE_PREFIX(getActiveUserId());
  keys.forEach((key) => {
    if (key.startsWith(prefix)) {
      if (!pattern || pattern.test(key)) {
        localStorage.removeItem(key);
      }
    }
  });
}

function clearOldestCaches(): void {
  if (!isCacheEnabled()) return;
  const caches: Array<{ key: string; timestamp: number }> = [];

  Object.keys(localStorage).forEach((key) => {
    if (key.startsWith(CACHE_PREFIX(getActiveUserId()))) {
      try {
        const metadata = JSON.parse(localStorage.getItem(key) || '{}');
        caches.push({ key, timestamp: metadata.timestamp || 0 });
      } catch {
        localStorage.removeItem(key);
      }
    }
  });

  caches.sort((a, b) => a.timestamp - b.timestamp);
  const toRemove = Math.ceil(caches.length * 0.25);
  caches.slice(0, toRemove).forEach(({ key }) => {
    localStorage.removeItem(key);
  });
}

export function getCacheStats(): {
  count: number;
  totalSize: number;
  oldestAge: number;
} {
  if (!isCacheEnabled()) {
    return { count: 0, totalSize: 0, oldestAge: 0 };
  }
  let count = 0;
  let totalSize = 0;
  let oldestTimestamp = Date.now();
  const prefix = CACHE_PREFIX(getActiveUserId());

  Object.keys(localStorage).forEach((key) => {
    if (key.startsWith(prefix)) {
      count += 1;
      const value = localStorage.getItem(key) || '';
      totalSize += new Blob([value]).size;

      try {
        const metadata = JSON.parse(value);
        if (metadata.timestamp < oldestTimestamp) {
          oldestTimestamp = metadata.timestamp;
        }
      } catch {
        return;
      }
    }
  });

  return {
    count,
    totalSize,
    oldestAge: Date.now() - oldestTimestamp
  };
}

export function clearMemoryCache(keys?: string[]): void {
  if (!keys) {
    memoryCache.clear();
    memoryKeys.length = 0;
    return;
  }
  keys.forEach((key) => {
    memoryCache.delete(key);
  });
  for (let i = memoryKeys.length - 1; i >= 0; i -= 1) {
    if (keys.includes(memoryKeys[i])) {
      memoryKeys.splice(i, 1);
    }
  }
}

export function clearInFlight(): void {
  inFlightRequests.clear();
}

export function revalidateInBackground<T>(
  cacheKey: string,
  apiFetcher: () => Promise<T>,
  config: CacheConfig = {}
): void {
  const now = Date.now();
  const last = revalidateAt.get(cacheKey) || 0;
  if (now - last < REVALIDATE_DEBOUNCE_MS) {
    return;
  }
  revalidateAt.set(cacheKey, now);
  apiFetcher()
    .then((fresh) => {
      setCachedData(cacheKey, fresh, config);
      remember(cacheKey, fresh);
    })
    .catch(() => {
      // Swallow background errors.
    });
}

export function listenForStorageEvents(): () => void {
  if (!browser) return () => undefined;

  const handler = (event: StorageEvent) => {
    if (!event.key) return;
    const prefix = CACHE_PREFIX(getActiveUserId());
    if (event.key.startsWith(prefix)) {
      const key = event.key.slice(prefix.length);
      clearMemoryCache([key]);
    }
  };

  window.addEventListener('storage', handler);
  return () => window.removeEventListener('storage', handler);
}

export async function loadData<T>(
  cacheKey: string,
  apiFetcher: () => Promise<T>,
  options: CacheConfig = {}
): Promise<T> {
  if (inFlightRequests.has(cacheKey)) {
    return inFlightRequests.get(cacheKey) as Promise<T>;
  }

  if (memoryCache.has(cacheKey)) {
    touch(cacheKey);
    return memoryCache.get(cacheKey) as T;
  }

  const cached = getCachedData<T>(cacheKey, options);
  if (cached) {
    if (options.staleWhileRevalidate && isCacheStale(cacheKey, options.ttl)) {
      revalidateInBackground(cacheKey, apiFetcher, options);
    }
    return cached;
  }

  const request = apiFetcher()
    .then((fresh) => {
      setCachedData(cacheKey, fresh, options);
      remember(cacheKey, fresh);
      return fresh;
    })
    .finally(() => {
      inFlightRequests.delete(cacheKey);
    });

  inFlightRequests.set(cacheKey, request);
  return request;
}
