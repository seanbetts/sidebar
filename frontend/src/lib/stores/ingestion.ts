import { writable } from 'svelte/store';
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

  return {
    subscribe,
    async load() {
      update(state => ({ ...state, loading: true, error: null }));
      try {
        const data = await ingestionAPI.list();
        set({ items: data.items || [], loading: false, error: null });
      } catch (error) {
        console.error('Failed to load ingestion status:', error);
        update(state => ({ ...state, loading: false, error: 'Failed to load uploads.' }));
      }
    }
  };
}

export const ingestionStore = createIngestionStore();
