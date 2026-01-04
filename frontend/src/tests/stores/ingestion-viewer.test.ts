import { beforeEach, describe, expect, it, vi } from 'vitest';
import { get } from 'svelte/store';
import { ingestionViewerStore } from '$lib/stores/ingestion-viewer';

const { ingestionAPI } = vi.hoisted(() => ({
  ingestionAPI: {
    get: vi.fn()
  }
}));

vi.mock('$lib/services/api', () => ({ ingestionAPI }));

describe('ingestionViewerStore', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    ingestionViewerStore.clearActive();
  });

  it('opens a file and sets active metadata', async () => {
    ingestionAPI.get.mockResolvedValue({
      file: { id: 'file-1' },
      job: { id: 'job-1' },
      derivatives: [],
      recommended_viewer: null
    });

    await ingestionViewerStore.open('file-1');

    expect(get(ingestionViewerStore).active?.file.id).toBe('file-1');
  });

  it('handles load errors', async () => {
    ingestionAPI.get.mockRejectedValue(new Error('fail'));

    await ingestionViewerStore.open('file-2');

    expect(get(ingestionViewerStore).error).toBe('Failed to load file.');
  });

  it('updates active job fields', () => {
    ingestionViewerStore.setLocalActive({
      file: { id: 'file-3' } as any,
      job: { id: 'job-3' } as any,
      recommended_viewer: null
    } as any);

    ingestionViewerStore.updateActiveJob('file-3', { status: 'done' } as any);

    expect(get(ingestionViewerStore).active?.job?.status).toBe('done');
  });
});
