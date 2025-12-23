import { writable } from 'svelte/store';

function createScratchpadStore() {
  const { subscribe, update } = writable({ version: 0 });

  return {
    subscribe,
    bump() {
      update(state => ({ version: state.version + 1 }));
    }
  };
}

export const scratchpadStore = createScratchpadStore();
