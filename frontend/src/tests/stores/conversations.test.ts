import { beforeEach, describe, expect, it, vi } from 'vitest';
import { get } from 'svelte/store';
import { conversationListStore } from '$lib/stores/conversations';

const cacheState = new Map<string, unknown>();

const conversationsAPI = {
  list: vi.fn(),
  search: vi.fn(),
  delete: vi.fn()
};

vi.mock('$lib/services/api', () => ({
  conversationsAPI
}));

vi.mock('$lib/utils/cache', () => ({
  getCachedData: vi.fn((key: string) => cacheState.get(key) ?? null),
  setCachedData: vi.fn((key: string, value: unknown) => cacheState.set(key, value)),
  isCacheStale: vi.fn(() => false),
  invalidateCache: vi.fn()
}));

vi.mock('$lib/utils/cacheEvents', () => ({
  dispatchCacheEvent: vi.fn()
}));

describe('conversationListStore', () => {
  beforeEach(() => {
    cacheState.clear();
    vi.clearAllMocks();
  });

  it('loads conversations from cache when available', async () => {
    const cached = [
      {
        id: '1',
        title: 'Cached',
        titleGenerated: false,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        messageCount: 1
      }
    ];
    cacheState.set('conversations.list', cached);

    await conversationListStore.load();

    const state = get(conversationListStore);
    expect(state.conversations).toEqual(cached);
    expect(conversationsAPI.list).not.toHaveBeenCalled();
  });

  it('fetches conversations when cache is empty', async () => {
    const remote = [
      {
        id: '2',
        title: 'Remote',
        titleGenerated: true,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        messageCount: 2
      }
    ];
    conversationsAPI.list.mockResolvedValue(remote);

    await conversationListStore.load(true);

    const state = get(conversationListStore);
    expect(conversationsAPI.list).toHaveBeenCalled();
    expect(state.conversations).toEqual(remote);
  });
});
