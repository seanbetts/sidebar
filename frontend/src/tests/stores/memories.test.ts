import { beforeEach, describe, expect, it, vi } from 'vitest';
import { get } from 'svelte/store';
import { memoriesStore } from '$lib/stores/memories';

const { memoriesAPI } = vi.hoisted(() => ({
  memoriesAPI: {
    list: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn()
  }
}));

vi.mock('$lib/services/memories', () => ({ memoriesAPI }));

describe('memoriesStore', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('loads and sorts memories by path', async () => {
    memoriesAPI.list.mockResolvedValue([
      { id: '2', path: 'zeta', content: 'b' },
      { id: '1', path: 'alpha', content: 'a' }
    ]);

    await memoriesStore.load();

    const state = get(memoriesStore);
    expect(state.memories[0].path).toBe('alpha');
  });

  it('creates a memory and updates store', async () => {
    memoriesAPI.create.mockResolvedValue({ id: '3', path: 'beta', content: 'c' });

    const result = await memoriesStore.create({ path: 'beta', content: 'c' });

    expect(result?.id).toBe('3');
    expect(get(memoriesStore).memories.some((item) => item.id === '3')).toBe(true);
  });

  it('deletes a memory by id', async () => {
    memoriesAPI.list.mockResolvedValue([{ id: '4', path: 'path', content: 'x' }]);
    memoriesAPI.delete.mockResolvedValue(undefined);
    await memoriesStore.load();

    await memoriesStore.delete('4');

    expect(get(memoriesStore).memories).toHaveLength(0);
  });
});
