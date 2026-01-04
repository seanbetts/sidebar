import { writable } from 'svelte/store';
import { ingestionAPI } from '$lib/services/api';
import { logError } from '$lib/utils/errorHandling';
import type { IngestionListItem, IngestionMetaResponse } from '$lib/types/ingestion';

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
        logError('Failed to load ingested file', error, { scope: 'ingestionViewerStore.open', fileId });
        update(state => ({
          ...state,
          loading: false,
          error: 'Failed to load file.',
          active: null
        }));
      }
    },
    setLocalActive(item: IngestionListItem) {
      const localMeta: IngestionMetaResponse = {
        file: item.file,
        job: item.job,
        derivatives: [],
        recommended_viewer: item.recommended_viewer ?? null
      };
      update(state => ({ ...state, active: localMeta, loading: false, error: null }));
    },
    updateActiveJob(fileId: string, patch: Partial<IngestionMetaResponse['job']>) {
      update(state => {
        if (!state.active || state.active.file.id !== fileId) {
          return state;
        }
        return {
          ...state,
          active: {
            ...state.active,
            job: { ...state.active.job, ...patch }
          }
        };
      });
    },
    setActive(meta: IngestionMetaResponse) {
      update(state => ({ ...state, active: meta, loading: false, error: null }));
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
