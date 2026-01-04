import { beforeEach, describe, expect, it, vi } from 'vitest';
import { get } from 'svelte/store';
import { thingsStore } from '$lib/stores/things';

const cacheState = new Map<string, unknown>();

const thingsAPI = {
  list: vi.fn(),
  counts: vi.fn(),
  areaTasks: vi.fn(),
  projectTasks: vi.fn(),
  search: vi.fn(),
  diagnostics: vi.fn(),
  apply: vi.fn()
};

vi.mock('$lib/services/api', () => ({
  thingsAPI
}));

vi.mock('$lib/utils/cache', () => ({
  getCachedData: vi.fn((key: string) => cacheState.get(key) ?? null),
  setCachedData: vi.fn((key: string, value: unknown) => cacheState.set(key, value)),
  isCacheStale: vi.fn(() => false)
}));

describe('thingsStore', () => {
  beforeEach(() => {
    cacheState.clear();
    vi.clearAllMocks();
    thingsStore.reset();
  });

  it('loads cached counts when available', async () => {
    const cachedCounts = {
      counts: { inbox: 1, today: 2, upcoming: 3 },
      areas: [],
      projects: []
    };
    cacheState.set('things.counts', cachedCounts);

    await thingsStore.loadCounts();

    const state = get(thingsStore);
    expect(state.todayCount).toBe(2);
    expect(state.counts.today).toBe(2);
    expect(thingsAPI.counts).not.toHaveBeenCalled();
  });

  it('defaults new tasks to the Home area when available', async () => {
    thingsAPI.list.mockResolvedValue({
      scope: 'today',
      tasks: [],
      areas: [{ id: 'area-home', title: 'Home' }],
      projects: []
    });

    await thingsStore.load({ type: 'today' });
    thingsStore.startNewTask();

    const state = get(thingsStore);
    expect(state.newTaskDraft?.listId).toBe('area-home');
    expect(state.newTaskDraft?.areaId).toBe('area-home');
  });
});
