import { get, writable } from 'svelte/store';
import { ingestionAPI } from '$lib/services/api';
import { getCachedData, isCacheStale, setCachedData } from '$lib/utils/cache';
import type { IngestionListItem } from '$lib/types/ingestion';

interface IngestionState {
  items: IngestionListItem[];
  localUploads: IngestionListItem[];
  loading: boolean;
  error: string | null;
  loaded: boolean;
}

const CACHE_KEY = 'ingestion.list';
const CACHE_TTL = 2 * 60 * 1000;
const CACHE_VERSION = '1.0';

function mergeWithLocalUploads(
  items: IngestionListItem[],
  localUploads: IngestionListItem[]
): IngestionListItem[] {
  const localIds = new Set(localUploads.map(item => item.file.id));
  const serverItems = items.filter(item => !localIds.has(item.file.id));
  return [...localUploads, ...serverItems];
}

function sortByCreatedAt(items: IngestionListItem[]): IngestionListItem[] {
  return [...items].sort((a, b) => (b.file.created_at || '').localeCompare(a.file.created_at || ''));
}

function persistCache(items: IngestionListItem[], localUploads: IngestionListItem[]) {
  const localIds = new Set(localUploads.map(item => item.file.id));
  const serverItems = items.filter(item => !localIds.has(item.file.id));
  setCachedData(CACHE_KEY, serverItems, { ttl: CACHE_TTL, version: CACHE_VERSION });
}

function createIngestionStore() {
  const { subscribe, update, set } = writable<IngestionState>({
    items: [],
    localUploads: [],
    loading: false,
    error: null,
    loaded: false
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
    addLocalSource(source: { id: string; name: string; mime: string; url: string }) {
      const now = new Date().toISOString();
      const upload: IngestionListItem = {
        file: {
          id: source.id,
          filename_original: source.name,
          mime_original: source.mime,
          size_bytes: 0,
          source_url: source.url,
          created_at: now
        },
        job: {
          status: 'uploading',
          stage: 'uploading',
          attempts: 0,
          user_message: 'Validating link...',
          progress: 0
        },
        recommended_viewer: 'viewer_video'
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
        const nextItems = state.items.filter(item => item.file.id !== fileId);
        persistCache(nextItems, nextUploads);
        return {
          ...state,
          localUploads: nextUploads,
          items: nextItems
        };
      });
    },
    removeItem(fileId: string) {
      update(state => {
        const nextUploads = state.localUploads.filter(item => item.file.id !== fileId);
        const nextItems = state.items.filter(item => item.file.id !== fileId);
        persistCache(nextItems, nextUploads);
        return {
          ...state,
          localUploads: nextUploads,
          items: nextItems
        };
      });
    },
    updatePinned(fileId: string, pinned: boolean) {
      update(state => {
        const nextItems = state.items.map(item =>
          item.file.id === fileId
            ? { ...item, file: { ...item.file, pinned } }
            : item
        );
        persistCache(nextItems, state.localUploads);
        return {
          ...state,
          items: nextItems
        };
      });
    },
    updateFilename(fileId: string, filename: string) {
      update(state => {
        const nextItems = state.items.map(item =>
          item.file.id === fileId
            ? { ...item, file: { ...item.file, filename_original: filename } }
            : item
        );
        persistCache(nextItems, state.localUploads);
        return {
          ...state,
          items: nextItems
        };
      });
    },
    upsertItem(item: IngestionListItem) {
      update(state => {
        const nextUploads = state.localUploads.filter(local => local.file.id !== item.file.id);
        const filtered = state.items.filter(existing => existing.file.id !== item.file.id);
        const nextItems = sortByCreatedAt([...filtered, item]);
        persistCache(nextItems, nextUploads);
        return {
          ...state,
          localUploads: nextUploads,
          items: nextItems
        };
      });
    },
    async load() {
      const currentState = get({ subscribe });
      if (!currentState.loaded) {
        const cached = getCachedData<IngestionListItem[]>(CACHE_KEY, {
          ttl: CACHE_TTL,
          version: CACHE_VERSION
        });
        if (cached) {
          update(state => ({
            ...state,
            items: mergeWithLocalUploads(cached, state.localUploads),
            loading: false,
            error: null,
            loaded: true
          }));
          if (isCacheStale(CACHE_KEY, CACHE_TTL)) {
            this.revalidateInBackground();
          }
          return;
        }
      }
      update(state => ({ ...state, loading: true, error: null }));
      try {
        const data = await ingestionAPI.list();
        const localUploads = get({ subscribe }).localUploads;
        setCachedData(CACHE_KEY, data.items || [], { ttl: CACHE_TTL, version: CACHE_VERSION });
        set({
          items: mergeWithLocalUploads(data.items || [], localUploads),
          localUploads,
          loading: false,
          error: null,
          loaded: true
        });
      } catch (error) {
        console.error('Failed to load ingestion status:', error);
        update(state => ({ ...state, loading: false, error: 'Failed to load uploads.', loaded: false }));
      }
    },
    async revalidateInBackground() {
      try {
        const data = await ingestionAPI.list();
        const localUploads = get({ subscribe }).localUploads;
        setCachedData(CACHE_KEY, data.items || [], { ttl: CACHE_TTL, version: CACHE_VERSION });
        update(state => ({
          ...state,
          items: mergeWithLocalUploads(data.items || [], localUploads),
          error: null,
          loaded: true
        }));
      } catch (error) {
        console.error('Failed to revalidate ingestion status:', error);
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
