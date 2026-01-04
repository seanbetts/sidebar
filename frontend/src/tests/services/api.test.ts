import { afterEach, describe, expect, it, vi } from 'vitest';
import { conversationsAPI, ingestionAPI, notesAPI, websitesAPI, thingsAPI } from '$lib/services/api';

const okJson = (value: unknown) =>
  Promise.resolve({
    ok: true,
    json: async () => value
  } as Response);

const failJson = (status = 500, message = 'Error') =>
  Promise.resolve({
    ok: false,
    status,
    json: async () => ({ detail: message })
  } as Response);

describe('api services', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('conversationsAPI.list returns conversations', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(okJson([{ id: '1' }]));

    const data = await conversationsAPI.list();

    expect(data).toEqual([{ id: '1' }]);
  });

  it('notesAPI.search throws on failure', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(failJson());

    await expect(notesAPI.search('query')).rejects.toThrow('Failed to search notes');
  });

  it('websitesAPI.list returns items', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(okJson({ items: [] }));

    const data = await websitesAPI.list();

    expect(data.items).toEqual([]);
  });

  it('ingestionAPI.list throws on failure', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(failJson());

    await expect(ingestionAPI.list()).rejects.toThrow('Failed to list ingestions');
  });

  it('thingsAPI.counts falls back on 404', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(
      Promise.resolve({
        ok: false,
        status: 404
      } as Response)
    );

    const data = await thingsAPI.counts();

    expect(data.counts.today).toBe(0);
    expect(data.areas).toEqual([]);
  });
});
