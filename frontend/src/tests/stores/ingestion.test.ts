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

describe('ingestionStore', () => {
  beforeEach(() => {
    cacheState.clear();
    vi.clearAllMocks();
    ingestionStore.stopPolling();
  });

  it('adds a local upload and tracks it', () => {
    const upload = ingestionStore.addLocalUpload({
      id: 'file-1',
      name: 'test.txt',
      type: 'text/plain',
      size: 12
    });

    const state = get(ingestionStore);
    expect(state.localUploads).toHaveLength(1);
    expect(state.items).toHaveLength(1);
    expect(state.items[0].file.id).toBe('file-1');
    expect(upload.job.status).toBe('uploading');

    ingestionStore.removeLocalUpload('file-1');
  });

  it('loads cached ingestion items when available', async () => {
    const cached = [
      {
        file: { id: 'file-2', filename_original: 'cached.txt', mime_original: 'text/plain', size_bytes: 1 },
        job: { status: 'ready', stage: 'complete', attempts: 0 },
        recommended_viewer: null
      }
    ];
    cacheState.set('ingestion.list', cached);

    await ingestionStore.load();

    const state = get(ingestionStore);
    expect(state.items).toHaveLength(1);
    expect(state.items[0].file.id).toBe('file-2');
    expect(ingestionAPI.list).not.toHaveBeenCalled();
  });
});
