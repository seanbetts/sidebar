import { beforeEach, describe, expect, it, vi } from 'vitest';
import { get } from 'svelte/store';
import { ingestionStore } from '$lib/stores/ingestion';

const cacheState = new Map<string, unknown>();

const { ingestionAPI } = vi.hoisted(() => ({
  ingestionAPI: {
    list: vi.fn()
  }
}));

vi.mock('$lib/services/api', () => ({
  ingestionAPI
}));

vi.mock('$lib/utils/cache', () => ({
  getCachedData: vi.fn((key: string) => cacheState.get(key) ?? null),
  setCachedData: vi.fn((key: string, value: unknown) => cacheState.set(key, value)),
  isCacheStale: vi.fn(() => false)
}));

const resetStore = () => {
  const state = get(ingestionStore);
  const ids = new Set([
    ...state.items.map((item) => item.file.id),
    ...state.localUploads.map((item) => item.file.id)
  ]);
  ids.forEach((fileId) => ingestionStore.removeItem(fileId));
};

describe('ingestionStore', () => {
  beforeEach(() => {
    cacheState.clear();
    vi.clearAllMocks();
    resetStore();
  });

  it('tracks local uploads and progress updates', () => {
    ingestionStore.addLocalUpload({
      id: 'file-1',
      name: 'doc.pdf',
      type: 'application/pdf',
      size: 2048
    });
    ingestionStore.updateLocalUploadProgress('file-1', 55.4);

    const state = get(ingestionStore);
    expect(state.localUploads).toHaveLength(1);
    expect(state.items).toHaveLength(1);
    expect(state.localUploads[0].job.progress).toBe(55);
    expect(state.localUploads[0].job.user_message).toBe('Uploading 55%');
  });

  it('updates pinned state and order', () => {
    ingestionStore.upsertItem({
      file: {
        id: 'file-2',
        filename_original: 'report.pdf',
        mime_original: 'application/pdf',
        size_bytes: 123,
        created_at: new Date().toISOString()
      },
      job: {
        status: 'ready',
        stage: 'ready',
        attempts: 0
      },
      recommended_viewer: null
    });

    ingestionStore.updatePinned('file-2', true);

    const state = get(ingestionStore);
    expect(state.items[0].file.pinned).toBe(true);
    expect(state.items[0].file.pinned_order).toBe(0);
  });

  it('updates file fields and job metadata', () => {
    ingestionStore.upsertItem({
      file: {
        id: 'file-3',
        filename_original: 'orig.txt',
        mime_original: 'text/plain',
        size_bytes: 3,
        created_at: new Date().toISOString()
      },
      job: { status: 'processing', stage: 'processing', attempts: 0 },
      recommended_viewer: null
    });

    ingestionStore.updateFileFields('file-3', { filename_original: 'renamed.txt' });
    ingestionStore.updateJob('file-3', { status: 'ready' });

    const state = get(ingestionStore);
    expect(state.items[0].file.filename_original).toBe('renamed.txt');
    expect(state.items[0].job.status).toBe('ready');
  });

  it('loads from cache without hitting the API', async () => {
    cacheState.set('ingestion.list', [
      {
        file: {
          id: 'cached',
          filename_original: 'cached.txt',
          mime_original: 'text/plain',
          size_bytes: 10,
          created_at: new Date().toISOString()
        },
        job: { status: 'ready', stage: 'ready', attempts: 0 },
        recommended_viewer: null
      }
    ]);

    await ingestionStore.load();

    const state = get(ingestionStore);
    expect(state.items).toHaveLength(1);
    expect(ingestionAPI.list).not.toHaveBeenCalled();
  });

  it('fetches ingestion list when cache is empty', async () => {
    ingestionAPI.list.mockResolvedValue({ items: [] });

    await ingestionStore.load();

    expect(ingestionAPI.list).toHaveBeenCalled();
  });

  it('revalidates in background and updates cache', async () => {
    ingestionAPI.list.mockResolvedValue({ items: [] });

    await ingestionStore.revalidateInBackground();

    expect(ingestionAPI.list).toHaveBeenCalled();
  });

  it('polls while uploads are active', () => {
    vi.useFakeTimers();
    ingestionStore.upsertItem({
      file: {
        id: 'active',
        filename_original: 'active.txt',
        mime_original: 'text/plain',
        size_bytes: 1,
        created_at: new Date().toISOString()
      },
      job: { status: 'processing', stage: 'processing', attempts: 0 },
      recommended_viewer: null
    });

    const loadSpy = vi.spyOn(ingestionStore, 'load').mockResolvedValue(undefined);
    ingestionStore.startPolling(1000);
    vi.advanceTimersByTime(1000);

    expect(loadSpy).toHaveBeenCalled();
    ingestionStore.stopPolling();
    vi.useRealTimers();
  });
});
