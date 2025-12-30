import { writable } from 'svelte/store';
import { getCachedData, setCachedData } from '$lib/utils/cache';

const CACHE_KEY = 'scratchpad.content';
const CACHE_TTL = 7 * 24 * 60 * 60 * 1000;
const CACHE_VERSION = '1.0';

function createScratchpadStore() {
  const { subscribe, update } = writable({ version: 0 });

  return {
    subscribe,
    bump() {
      update(state => ({ version: state.version + 1 }));
    },
    getCachedContent(): string | null {
      return getCachedData<string>(CACHE_KEY, { ttl: CACHE_TTL, version: CACHE_VERSION });
    },
    setCachedContent(content: string) {
      setCachedData(CACHE_KEY, content, { ttl: CACHE_TTL, version: CACHE_VERSION });
    }
  };
}

export const scratchpadStore = createScratchpadStore();
