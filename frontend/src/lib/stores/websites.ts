import { writable } from 'svelte/store';

export interface WebsiteItem {
  id: string;
  title: string;
  url: string;
  domain: string;
  saved_at: string | null;
  published_at: string | null;
  pinned: boolean;
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
  }>({
    items: [],
    loading: false,
    error: null,
    active: null,
    loadingDetail: false
  });

  return {
    subscribe,

    async load() {
      update(state => ({ ...state, loading: true, error: null }));
      try {
        const response = await fetch('/api/websites');
        if (!response.ok) throw new Error('Failed to load websites');
        const data = await response.json();
        update(state => ({
          ...state,
          items: data.items || [],
          loading: false,
          error: null
        }));
      } catch (error) {
        console.error('Failed to load websites:', error);
        update(state => ({ ...state, loading: false, error: 'Failed to load websites' }));
      }
    },

    async loadById(id: string) {
      update(state => ({ ...state, loadingDetail: true, error: null }));
      try {
        const response = await fetch(`/api/websites/${id}`);
        if (!response.ok) throw new Error('Failed to load website');
        const data = await response.json();
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

    clearActive() {
      update(state => ({ ...state, active: null }));
    },

    reset() {
      set({ items: [], loading: false, error: null, active: null, loadingDetail: false });
    }
  };
}

export const websitesStore = createWebsitesStore();
