import { get, writable } from 'svelte/store';
import { ingestionAPI } from '$lib/services/api';
import type { IngestionListItem } from '$lib/types/ingestion';

interface IngestionState {
  items: IngestionListItem[];
  localUploads: IngestionListItem[];
  loading: boolean;
  error: string | null;
}

function createIngestionStore() {
  const { subscribe, update, set } = writable<IngestionState>({
    items: [],
    localUploads: [],
    loading: false,
    error: null
  });
  let pollingId: ReturnType<typeof setInterval> | null = null;

  return {
    subscribe,
    addLocalUpload(file: { id: string; name: string; type: string; size: number }) {
      const now = new Date().toISOString();
      const upload: IngestionListItem = {
        file: {
          id: file.id,
          filename_original: file.name,
          mime_original: file.type || 'application/octet-stream',
          size_bytes: file.size,
          created_at: now
        },
        job: {
          status: 'uploading',
          stage: 'uploading',
          attempts: 0,
          user_message: 'Uploading 0%',
          progress: 0
        },
        recommended_viewer: null
      };
      update(state => ({
        ...state,
        localUploads: [...state.localUploads, upload],
        items: [...state.localUploads, upload, ...state.items]
      }));
      return upload;
    },
    updateLocalUploadProgress(fileId: string, progress: number) {
      const percent = Math.max(0, Math.min(100, Math.round(progress)));
      update(state => {
        const nextUploads = state.localUploads.map(item => {
          if (item.file.id !== fileId) return item;
          return {
            ...item,
            job: {
              ...item.job,
              progress: percent,
              user_message: `Uploading ${percent}%`
            }
          };
        });
        const nextItems = state.items.map(item => {
          if (item.file.id !== fileId) return item;
          return nextUploads.find(local => local.file.id === fileId) ?? item;
        });
        return {
          ...state,
          localUploads: nextUploads,
          items: nextItems
        };
      });
    },
    removeLocalUpload(fileId: string) {
      update(state => {
        const nextUploads = state.localUploads.filter(item => item.file.id !== fileId);
        return {
          ...state,
          localUploads: nextUploads,
          items: state.items.filter(item => item.file.id !== fileId)
        };
      });
    },
    updatePinned(fileId: string, pinned: boolean) {
      update(state => ({
        ...state,
        items: state.items.map(item =>
          item.file.id === fileId
            ? { ...item, file: { ...item.file, pinned } }
            : item
        )
      }));
    },
    updateFilename(fileId: string, filename: string) {
      update(state => ({
        ...state,
        items: state.items.map(item =>
          item.file.id === fileId
            ? { ...item, file: { ...item.file, filename_original: filename } }
            : item
        )
      }));
    },
    async load() {
      update(state => ({ ...state, loading: true, error: null }));
      try {
        const data = await ingestionAPI.list();
        const localUploads = get({ subscribe }).localUploads;
        set({
          items: [...localUploads, ...(data.items || [])],
          localUploads,
          loading: false,
          error: null
        });
      } catch (error) {
        console.error('Failed to load ingestion status:', error);
        update(state => ({ ...state, loading: false, error: 'Failed to load uploads.' }));
      }
    },
    startPolling(intervalMs: number = 5000) {
      if (pollingId) return;
      pollingId = setInterval(() => {
        const state = get({ subscribe });
        const hasActive = state.items.some(
          item => !['ready', 'failed', 'canceled'].includes(item.job.status || '')
        );
        if (hasActive) {
          void this.load();
        } else {
          this.stopPolling();
        }
      }, intervalMs);
    },
    stopPolling() {
      if (pollingId) {
        clearInterval(pollingId);
        pollingId = null;
      }
    }
  };
}

export const ingestionStore = createIngestionStore();
