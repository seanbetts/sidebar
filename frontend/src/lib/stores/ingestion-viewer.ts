import { writable } from 'svelte/store';
import { ingestionAPI } from '$lib/services/api';
import type { IngestionMetaResponse } from '$lib/types/ingestion';

interface IngestionViewerState {
  active: IngestionMetaResponse | null;
  loading: boolean;
  error: string | null;
}

function createIngestionViewerStore() {
  const { subscribe, update } = writable<IngestionViewerState>({
    active: null,
    loading: false,
    error: null
  });

  return {
    subscribe,
    async open(fileId: string) {
      update(state => ({ ...state, loading: true, error: null }));
      try {
        const data = await ingestionAPI.get(fileId);
        update(state => ({ ...state, active: data, loading: false, error: null }));
      } catch (error) {
        console.error('Failed to load ingested file:', error);
        update(state => ({
          ...state,
          loading: false,
          error: 'Failed to load file.',
          active: null
        }));
      }
    },
    updatePinned(fileId: string, pinned: boolean) {
      update(state => {
        if (!state.active || state.active.file.id !== fileId) {
          return state;
        }
        return {
          ...state,
          active: {
            ...state.active,
            file: { ...state.active.file, pinned }
          }
        };
      });
    },
    updateFilename(fileId: string, filename: string) {
      update(state => {
        if (!state.active || state.active.file.id !== fileId) {
          return state;
        }
        return {
          ...state,
          active: {
            ...state.active,
            file: { ...state.active.file, filename_original: filename }
          }
        };
      });
    },
    clearActive() {
      update(state => ({ ...state, active: null, error: null }));
    }
  };
}

export const ingestionViewerStore = createIngestionViewerStore();
