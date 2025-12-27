import { get, writable } from 'svelte/store';
import { websitesAPI } from '$lib/services/api';

export interface WebsiteItem {
  id: string;
  title: string;
  url: string;
  domain: string;
  saved_at: string | null;
  published_at: string | null;
  pinned: boolean;
  archived?: boolean;
  updated_at: string | null;
  last_opened_at: string | null;
}

export interface WebsiteDetail extends WebsiteItem {
  content: string;
  source: string | null;
  url_full: string | null;
}

function createWebsitesStore() {
  const { subscribe, set, update } = writable<{
    items: WebsiteItem[];
    loading: boolean;
    error: string | null;
    active: WebsiteDetail | null;
    loadingDetail: boolean;
    searchQuery: string;
    loaded: boolean;
  }>({
    items: [],
    loading: false,
    error: null,
    active: null,
    loadingDetail: false,
    searchQuery: '',
    loaded: false
  });

  return {
    subscribe,

    async load(force: boolean = false) {
      if (!force) {
        const currentState = get({ subscribe });
        if (currentState.loaded && !currentState.searchQuery) {
          return;
        }
      }
      update(state => ({ ...state, loading: true, error: null, searchQuery: '' }));
      try {
        const data = await websitesAPI.list();
        update(state => ({
          ...state,
          items: data.items || [],
          loading: false,
          error: null,
          searchQuery: '',
          loaded: true
        }));
      } catch (error) {
        console.error('Failed to load websites:', error);
        update(state => ({ ...state, loading: false, error: 'Failed to load websites', searchQuery: '', loaded: false }));
      }
    },

    async loadById(id: string) {
      update(state => ({ ...state, loadingDetail: true, error: null }));
      try {
        const data = await websitesAPI.get(id);
        update(state => ({
          ...state,
          active: data,
          loadingDetail: false,
          error: null
        }));
      } catch (error) {
        console.error('Failed to load website:', error);
        update(state => ({ ...state, loadingDetail: false, error: 'Failed to load website' }));
      }
    },

    async search(query: string) {
      update(state => ({ ...state, loading: true, error: null, searchQuery: query }));
      try {
        const data = query
          ? await websitesAPI.search(query)
          : await websitesAPI.list();
        update(state => ({
          ...state,
          items: data.items || [],
          loading: false,
          error: null,
          searchQuery: query,
          loaded: true
        }));
      } catch (error) {
        console.error('Failed to search websites:', error);
        update(state => ({ ...state, loading: false, error: 'Failed to search websites', searchQuery: query, loaded: false }));
      }
    },

    clearActive() {
      update(state => ({ ...state, active: null }));
    },

    reset() {
      set({ items: [], loading: false, error: null, active: null, loadingDetail: false, searchQuery: '', loaded: false });
    }
  };
}

export const websitesStore = createWebsitesStore();
