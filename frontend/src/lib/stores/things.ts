import { writable } from 'svelte/store';
import { thingsAPI } from '$lib/services/api';
import type { ThingsArea, ThingsListResponse, ThingsProject, ThingsTask } from '$lib/types/things';

export type ThingsSelection =
  | { type: 'inbox' }
  | { type: 'today' }
  | { type: 'upcoming' }
  | { type: 'area'; id: string }
  | { type: 'project'; id: string };

type ThingsState = {
  selection: ThingsSelection;
  tasks: ThingsTask[];
  areas: ThingsArea[];
  projects: ThingsProject[];
  isLoading: boolean;
  error: string;
};

const defaultState: ThingsState = {
  selection: { type: 'today' },
  tasks: [],
  areas: [],
  projects: [],
  isLoading: false,
  error: ''
};

function createThingsStore() {
  const { subscribe, set, update } = writable<ThingsState>(defaultState);
  let loadToken = 0;
  const cache = new Map<string, { tasks: ThingsTask[]; timestamp: number }>();
  const cacheTtlMs = 30_000;

  const applyResponse = (response: ThingsListResponse) => {
    update((state) => ({
      ...state,
      tasks: response.tasks ?? [],
      areas: response.areas ?? state.areas,
      projects: response.projects ?? state.projects,
      error: ''
    }));
  };

  const selectionKey = (selection: ThingsSelection) => {
    if (selection.type === 'area' || selection.type === 'project') {
      return `${selection.type}:${selection.id}`;
    }
    return selection.type;
  };

  const loadSelection = async (selection: ThingsSelection) => {
    const token = ++loadToken;
    const key = selectionKey(selection);
    const cached = cache.get(key);
    if (cached && Date.now() - cached.timestamp < cacheTtlMs) {
      update((state) => ({
        ...state,
        selection,
        tasks: cached.tasks,
        isLoading: false,
        error: ''
      }));
      return;
    }
    update((state) => ({ ...state, selection, isLoading: true, error: '' }));
    try {
      let response: ThingsListResponse;
      if (selection.type === 'today' || selection.type === 'upcoming' || selection.type === 'inbox') {
        response = await thingsAPI.list(selection.type);
      } else if (selection.type === 'area') {
        response = await thingsAPI.areaTasks(selection.id);
      } else {
        response = await thingsAPI.projectTasks(selection.id);
      }
      if (token !== loadToken) return;
      cache.set(key, { tasks: response.tasks ?? [], timestamp: Date.now() });
      applyResponse(response);
    } catch (error) {
      if (token !== loadToken) return;
      update((state) => ({
        ...state,
        error: error instanceof Error ? error.message : 'Failed to load Things data'
      }));
    } finally {
      if (token !== loadToken) return;
      update((state) => ({ ...state, isLoading: false }));
    }
  };

  return {
    subscribe,
    reset: () => set(defaultState),
    load: (selection: ThingsSelection) => loadSelection(selection),
    completeTask: async (taskId: string) => {
      await thingsAPI.apply({ op: 'complete', id: taskId });
      update((state) => ({
        ...state,
        tasks: state.tasks.filter((task) => task.id !== taskId)
      }));
    }
  };
}

export const thingsStore = createThingsStore();
