import { get, writable } from 'svelte/store';
import { ingestionAPI } from '$lib/services/api';
import type { IngestionListItem } from '$lib/types/ingestion';

interface IngestionState {
  items: IngestionListItem[];
  loading: boolean;
  error: string | null;
}

function createIngestionStore() {
  const { subscribe, update, set } = writable<IngestionState>({
    items: [],
    loading: false,
    error: null
  });
  let pollingId: ReturnType<typeof setInterval> | null = null;

  return {
    subscribe,
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
    async load() {
      update(state => ({ ...state, loading: true, error: null }));
      try {
        const data = await ingestionAPI.list();
        set({ items: data.items || [], loading: false, error: null });
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
