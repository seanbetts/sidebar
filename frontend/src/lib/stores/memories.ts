import { writable } from 'svelte/store';
import type { Memory, MemoryCreate, MemoryUpdate } from '$lib/types/memory';
import { memoriesAPI } from '$lib/services/memories';

interface MemoryState {
  memories: Memory[];
  isLoading: boolean;
  error: string | null;
}

function sortMemories(items: Memory[]): Memory[] {
  return [...items].sort((a, b) => a.path.localeCompare(b.path));
}

function createMemoriesStore() {
  const { subscribe, set, update } = writable<MemoryState>({
    memories: [],
    isLoading: false,
    error: null
  });

  return {
    subscribe,

    async load() {
      update((state) => ({ ...state, isLoading: true, error: null }));
      try {
        const memories = await memoriesAPI.list();
        update((state) => ({
          ...state,
          memories: sortMemories(memories),
          isLoading: false
        }));
      } catch (error) {
        update((state) => ({
          ...state,
          isLoading: false,
          error: error instanceof Error ? error.message : 'Failed to load memories'
        }));
      }
    },

    async create(payload: MemoryCreate) {
      update((state) => ({ ...state, isLoading: true, error: null }));
      try {
        const memory = await memoriesAPI.create(payload);
        update((state) => ({
          ...state,
          memories: sortMemories([...state.memories, memory]),
          isLoading: false
        }));
        return memory;
      } catch (error) {
        update((state) => ({
          ...state,
          isLoading: false,
          error: error instanceof Error ? error.message : 'Failed to create memory'
        }));
        return null;
      }
    },

    async updateMemory(id: string, payload: MemoryUpdate) {
      update((state) => ({ ...state, isLoading: true, error: null }));
      try {
        const memory = await memoriesAPI.update(id, payload);
        update((state) => ({
          ...state,
          memories: sortMemories(
            state.memories.map((item) => (item.id === id ? memory : item))
          ),
          isLoading: false
        }));
        return memory;
      } catch (error) {
        update((state) => ({
          ...state,
          isLoading: false,
          error: error instanceof Error ? error.message : 'Failed to update memory'
        }));
        return null;
      }
    },

    async delete(id: string) {
      update((state) => ({ ...state, isLoading: true, error: null }));
      try {
        await memoriesAPI.delete(id);
        update((state) => ({
          ...state,
          memories: state.memories.filter((item) => item.id !== id),
          isLoading: false
        }));
      } catch (error) {
        update((state) => ({
          ...state,
          isLoading: false,
          error: error instanceof Error ? error.message : 'Failed to delete memory'
        }));
      }
    },

    clearError() {
      update((state) => ({ ...state, error: null }));
    }
  };
}

export const memoriesStore = createMemoriesStore();
