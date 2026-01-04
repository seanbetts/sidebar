import { describe, expect, it, vi, afterEach } from 'vitest';
import { memoriesAPI } from '$lib/services/memories';

const okJson = (value: unknown) =>
  Promise.resolve({
    ok: true,
    json: async () => value
  } as Response);

const fail = (status = 500) =>
  Promise.resolve({
    ok: false,
    status
  } as Response);

describe('MemoriesAPI', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('lists memories', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(okJson([{ id: '1' }]));
    const data = await memoriesAPI.list();
    expect(data).toEqual([{ id: '1' }]);
  });

  it('creates memories', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(okJson({ id: '2' }));
    const data = await memoriesAPI.create({ path: 'p', content: 'c' });
    expect(data.id).toBe('2');
  });

  it('throws on delete failure', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(fail());
    await expect(memoriesAPI.delete('1')).rejects.toThrow('Failed to delete memory');
  });
});
