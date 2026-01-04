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

  it('conversationsAPI.create posts a title', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockReturnValue(okJson({ id: 'c1' }));

    const data = await conversationsAPI.create('Hello');

    expect(data.id).toBe('c1');
    expect(fetchSpy).toHaveBeenCalledWith(
      '/api/v1/conversations/',
      expect.objectContaining({ method: 'POST' })
    );
  });

  it('conversationsAPI.get returns conversation data', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(okJson({ id: 'c2', messages: [] }));

    const data = await conversationsAPI.get('c2');

    expect(data.id).toBe('c2');
  });

  it('conversationsAPI.addMessage persists timestamps', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockReturnValue(okJson({}));
    const timestamp = new Date('2025-01-01T00:00:00Z');

    await conversationsAPI.addMessage('c1', {
      id: 'm1',
      role: 'user',
      content: 'Hi',
      status: 'sent',
      timestamp
    });

    expect(fetchSpy).toHaveBeenCalledWith(
      '/api/v1/conversations/c1/messages',
      expect.objectContaining({
        method: 'POST',
        body: expect.stringContaining(timestamp.toISOString())
      })
    );
  });

  it('conversationsAPI.update sends PUT', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockReturnValue(okJson({}));

    await conversationsAPI.update('c3', { title: 'Updated' });

    expect(fetchSpy).toHaveBeenCalledWith(
      '/api/v1/conversations/c3',
      expect.objectContaining({ method: 'PUT' })
    );
  });

  it('conversationsAPI.delete throws on failure', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(failJson());

    await expect(conversationsAPI.delete('c4')).rejects.toThrow('Failed to delete conversation');
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

  it('websitesAPI.search returns items', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(okJson({ items: [{ id: 'w1' }] }));

    const data = await websitesAPI.search('sidebar');

    expect(data.items).toHaveLength(1);
  });

  it('ingestionAPI.list throws on failure', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(failJson());

    await expect(ingestionAPI.list()).rejects.toThrow('Failed to list ingestions');
  });

  it('ingestionAPI.ingestYoutube surfaces API detail', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(failJson(400, 'Bad URL'));

    await expect(ingestionAPI.ingestYoutube('bad')).rejects.toThrow('Bad URL');
  });

  it('ingestionAPI.pause throws on failure', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(failJson());

    await expect(ingestionAPI.pause('file-1')).rejects.toThrow('Failed to pause ingestion');
  });

  it('ingestionAPI.cancel throws on failure', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(failJson());

    await expect(ingestionAPI.cancel('file-2')).rejects.toThrow('Failed to cancel ingestion');
  });

  it('ingestionAPI.rename posts filename', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockReturnValue(okJson({}));

    await ingestionAPI.rename('file-3', 'new.txt');

    expect(fetchSpy).toHaveBeenCalledWith(
      '/api/v1/ingestion/file-3/rename',
      expect.objectContaining({ method: 'PATCH' })
    );
  });

  it('ingestionAPI.setPinned updates state', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockReturnValue(okJson({}));

    await ingestionAPI.setPinned('file-2', true);

    expect(fetchSpy).toHaveBeenCalledWith(
      '/api/v1/ingestion/file-2/pin',
      expect.objectContaining({ method: 'PATCH' })
    );
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

  it('notesAPI.listTree returns children', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(okJson({ children: [{ id: 'n1' }] }));

    const data = await notesAPI.listTree();

    expect(data.children).toHaveLength(1);
  });

  it('thingsAPI.diagnostics falls back on 404', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(
      Promise.resolve({ ok: false, status: 404 } as Response)
    );

    const data = await thingsAPI.diagnostics();

    expect(data.dbAccess).toBe(false);
  });

  it('thingsAPI.status returns status payload', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(okJson({ online: true }));

    const data = await thingsAPI.status();

    expect(data.online).toBe(true);
  });

  it('thingsAPI.search returns list data', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(okJson({ tasks: [] }));

    const data = await thingsAPI.search('query');

    expect(data.tasks).toEqual([]);
  });

  it('thingsAPI.list returns list data', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(okJson({ scope: 'today', tasks: [] }));

    const data = await thingsAPI.list('today');

    expect(data.scope).toBe('today');
  });

  it('thingsAPI.projectTasks returns list data', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(okJson({ tasks: [{ id: 't1' }] }));

    const data = await thingsAPI.projectTasks('p1');

    expect(data.tasks?.[0].id).toBe('t1');
  });

  it('ingestionAPI.delete ignores 404', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(
      Promise.resolve({ ok: false, status: 404 } as Response)
    );

    await expect(ingestionAPI.delete('file-1')).resolves.toBeUndefined();
  });

  it('notesAPI.updatePinnedOrder throws on failure', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(failJson());

    await expect(notesAPI.updatePinnedOrder(['n1'])).rejects.toThrow('Failed to update pinned order');
  });

  it('websitesAPI.updatePinnedOrder throws on failure', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(failJson());

    await expect(websitesAPI.updatePinnedOrder(['w1'])).rejects.toThrow('Failed to update pinned order');
  });

  it('thingsAPI.apply throws on failure', async () => {
    vi.spyOn(global, 'fetch').mockReturnValue(failJson());

    await expect(thingsAPI.apply({ op: 'noop' })).rejects.toThrow('Failed to apply Things operation');
  });

  it('thingsAPI.setUrlToken posts the token', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockReturnValue(okJson({}));

    await thingsAPI.setUrlToken('token');

    expect(fetchSpy).toHaveBeenCalledWith(
      '/api/v1/things/bridges/url-token',
      expect.objectContaining({ method: 'POST' })
    );
  });

  it('ingestionAPI.upload resolves with response payload', async () => {
    class MockXHR {
      upload = {
        addEventListener: vi.fn((event: string, cb: (event: ProgressEvent) => void) => {
          if (event === 'progress') {
            cb({
              lengthComputable: true,
              loaded: 50,
              total: 100
            } as ProgressEvent);
          }
        })
      };
      onload: (() => void) | null = null;
      onerror: (() => void) | null = null;
      responseText = JSON.stringify({ file_id: 'file-123' });
      status = 200;
      withCredentials = false;
      open = vi.fn();
      send = vi.fn(() => {
        this.onload?.();
      });
    }

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (global as any).XMLHttpRequest = MockXHR;

    const result = await ingestionAPI.upload(new File(['content'], 'test.txt'));

    expect(result.file_id).toBe('file-123');
  });
});
