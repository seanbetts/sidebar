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

function createWebsitesStore() {
  const { subscribe, set, update } = writable<{
    items: WebsiteItem[];
    loading: boolean;
    error: string | null;
  }>({
    items: [],
    loading: false,
    error: null
  });

  return {
    subscribe,

    async load() {
      update(state => ({ ...state, loading: true, error: null }));
      try {
        const response = await fetch('/api/websites');
        if (!response.ok) throw new Error('Failed to load websites');
        const data = await response.json();
        set({ items: data.items || [], loading: false, error: null });
      } catch (error) {
        console.error('Failed to load websites:', error);
        update(state => ({ ...state, loading: false, error: 'Failed to load websites' }));
      }
    },

    reset() {
      set({ items: [], loading: false, error: null });
    }
  };
}

export const websitesStore = createWebsitesStore();
