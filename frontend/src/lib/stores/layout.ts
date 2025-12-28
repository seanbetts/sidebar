import { browser } from '$app/environment';
import { writable } from 'svelte/store';

export type LayoutMode = 'default' | 'chat-focused';

export interface LayoutState {
  mode: LayoutMode;
  chatPanelRatio: number;
}

const DEFAULT_STATE: LayoutState = {
  mode: 'default',
  chatPanelRatio: 0.38
};

const STORAGE_KEY = 'sideBar.layout';

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

function loadInitialState(): LayoutState {
  if (!browser) return DEFAULT_STATE;
  const stored = localStorage.getItem(STORAGE_KEY);
  if (!stored) return DEFAULT_STATE;
  try {
    const parsed = JSON.parse(stored) as Partial<LayoutState> & {
      chatSidebarRatio?: number;
      workspaceSidebarRatio?: number;
    };
    if (typeof parsed.chatPanelRatio === 'number') {
      return { ...DEFAULT_STATE, ...parsed };
    }
    if (typeof parsed.chatSidebarRatio === 'number') {
      return {
        ...DEFAULT_STATE,
        chatPanelRatio: parsed.chatSidebarRatio
      };
    }
    return DEFAULT_STATE;
  } catch {
    return DEFAULT_STATE;
  }
}

function createLayoutStore() {
  const { subscribe, update } = writable<LayoutState>(loadInitialState());

  return {
    subscribe,
    toggleMode: () =>
      update((state) => ({
        ...state,
        mode: state.mode === 'default' ? 'chat-focused' : 'default'
      })),
    setChatPanelRatio: (ratio: number) =>
      update((state) => ({
        ...state,
        chatPanelRatio: clamp(ratio, 0.2, 0.5)
      }))
  };
}

export const layoutStore = createLayoutStore();

layoutStore.subscribe((value) => {
  if (browser) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(value));
  }
});
