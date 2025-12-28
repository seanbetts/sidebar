import { browser } from '$app/environment';
import { writable } from 'svelte/store';

export type LayoutMode = 'default' | 'chat-focused';

export interface LayoutState {
  mode: LayoutMode;
  chatSidebarWidth: number;
  workspaceSidebarWidth: number;
}

const DEFAULT_STATE: LayoutState = {
  mode: 'default',
  chatSidebarWidth: 550,
  workspaceSidebarWidth: 650
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
    return JSON.parse(stored) as LayoutState;
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
    setChatSidebarWidth: (width: number) =>
      update((state) => ({
        ...state,
        chatSidebarWidth: clamp(width, 320, 900)
      })),
    setWorkspaceSidebarWidth: (width: number) =>
      update((state) => ({
        ...state,
        workspaceSidebarWidth: clamp(width, 480, 900)
      }))
  };
}

export const layoutStore = createLayoutStore();

layoutStore.subscribe((value) => {
  if (browser) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(value));
  }
});
