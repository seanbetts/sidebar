import { writable } from 'svelte/store';
import { thingsAPI } from '$lib/services/api';
import { getCachedData, isCacheStale, setCachedData } from '$lib/utils/cache';
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

type ThingsMetaCache = {
  areas: ThingsArea[];
  projects: ThingsProject[];
};

const CACHE_TTL = 2 * 60 * 1000;
const CACHE_VERSION = '1.0';
const META_CACHE_KEY = 'things.meta';

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

  const tasksCacheKey = (selection: ThingsSelection) => `things.tasks.${selectionKey(selection)}`;

  const loadSelection = async (selection: ThingsSelection) => {
    const token = ++loadToken;
    const key = tasksCacheKey(selection);
    const cachedTasks = getCachedData<ThingsTask[]>(key, { ttl: CACHE_TTL, version: CACHE_VERSION });
    const cachedMeta = getCachedData<ThingsMetaCache>(META_CACHE_KEY, {
      ttl: CACHE_TTL,
      version: CACHE_VERSION
    });
    if (cachedMeta) {
      update((state) => ({
        ...state,
        areas: cachedMeta.areas,
        projects: cachedMeta.projects
      }));
    }
    if (cachedTasks) {
      update((state) => ({
        ...state,
        selection,
        tasks: cachedTasks,
        isLoading: false,
        error: ''
      }));
      if (!isCacheStale(key, CACHE_TTL)) {
        return;
      }
    } else {
      update((state) => ({ ...state, selection, isLoading: true, error: '' }));
    }
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
      setCachedData(key, response.tasks ?? [], { ttl: CACHE_TTL, version: CACHE_VERSION });
      if (response.areas && response.projects) {
        setCachedData(
          META_CACHE_KEY,
          { areas: response.areas ?? [], projects: response.projects ?? [] },
          { ttl: CACHE_TTL, version: CACHE_VERSION }
        );
      }
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
      update((state) => {
        const nextTasks = state.tasks.filter((task) => task.id !== taskId);
        setCachedData(tasksCacheKey(state.selection), nextTasks, {
          ttl: CACHE_TTL,
          version: CACHE_VERSION
        });
        return {
          ...state,
          tasks: nextTasks
        };
      });
    }
  };
}

export const thingsStore = createThingsStore();
