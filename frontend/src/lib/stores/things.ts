import { writable } from 'svelte/store';
import { thingsAPI } from '$lib/services/api';
import { getCachedData, isCacheStale, setCachedData } from '$lib/utils/cache';
import type {
  ThingsArea,
  ThingsBridgeDiagnostics,
  ThingsCountsResponse,
  ThingsListResponse,
  ThingsProject,
  ThingsTask
} from '$lib/types/things';

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
  todayCount: number;
  counts: Record<string, number>;
  diagnostics: ThingsBridgeDiagnostics | null;
  syncNotice: string;
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
const COUNTS_CACHE_KEY = 'things.counts';

const defaultState: ThingsState = {
  selection: { type: 'today' },
  tasks: [],
  areas: [],
  projects: [],
  todayCount: 0,
  counts: {},
  diagnostics: null,
  syncNotice: '',
  isLoading: false,
  error: ''
};

function createThingsStore() {
  const { subscribe, set, update } = writable<ThingsState>(defaultState);
  let loadToken = 0;
  let hasPreloaded = false;
  let lastMeta: ThingsMetaCache = { areas: [], projects: [] };
  let syncNoticeTimer: ReturnType<typeof setTimeout> | null = null;

  const setSyncNotice = (message: string) => {
    if (syncNoticeTimer) {
      clearTimeout(syncNoticeTimer);
    }
    update((state) => ({ ...state, syncNotice: message }));
    syncNoticeTimer = setTimeout(() => {
      update((state) => ({ ...state, syncNotice: '' }));
    }, 6000);
  };

  const selectionCount = (
    selection: ThingsSelection,
    tasks: ThingsTask[],
    projects: ThingsProject[]
  ) => {
    if (selection.type !== 'area') return tasks.length;
    const projectIds = new Set(projects.map((project) => project.id));
    return tasks.filter((task) => !projectIds.has(task.id) && task.status !== 'project').length;
  };

  const toCountsMap = (counts: ThingsCountsResponse): Record<string, number> => {
    const map: Record<string, number> = {
      inbox: counts.counts.inbox ?? 0,
      today: counts.counts.today ?? 0,
      upcoming: counts.counts.upcoming ?? 0
    };
    counts.areas.forEach((area) => {
      map[`area:${area.id}`] = area.count;
    });
    counts.projects.forEach((project) => {
      map[`project:${project.id}`] = project.count;
    });
    return map;
  };

  const normalizeCountsCache = (
    cached: ThingsCountsResponse | Record<string, number>
  ): { map: Record<string, number>; todayCount: number } => {
    if ('counts' in cached) {
      const map = toCountsMap(cached);
      return { map, todayCount: cached.counts.today ?? 0 };
    }
    const todayCount = cached.today ?? cached.inbox ?? 0;
    return { map: cached, todayCount };
  };

  const applyCountsResponse = (counts: ThingsCountsResponse) => {
    const map = toCountsMap(counts);
    update((state) => ({
      ...state,
      counts: map,
      todayCount: counts.counts.today
    }));
    setCachedData(COUNTS_CACHE_KEY, counts, { ttl: CACHE_TTL, version: CACHE_VERSION });
  };

  const applyResponse = (response: ThingsListResponse, selection: ThingsSelection) => {
    const key = selectionKey(selection);
    lastMeta = {
      areas: response.areas ?? lastMeta.areas,
      projects: response.projects ?? lastMeta.projects
    };
    update((state) => ({
      ...state,
      tasks: response.tasks ?? [],
      areas: response.areas ?? state.areas,
      projects: response.projects ?? state.projects,
      todayCount:
        response.scope === 'today' ? (response.tasks ?? []).length : state.todayCount,
      counts: {
        ...state.counts,
        [key]: selectionCount(selection, response.tasks ?? [], response.projects ?? state.projects)
      },
      error: ''
    }));
  };

  const isSameSelection = (a: ThingsSelection, b: ThingsSelection) => {
    if (a.type !== b.type) return false;
    if (a.type === 'area' || a.type === 'project') {
      return a.id === (b as { id: string }).id;
    }
    return true;
  };

  const preloadAllSelections = (current: ThingsSelection) => {
    if (hasPreloaded) return;
    hasPreloaded = true;
    const baseSelections: ThingsSelection[] = [{ type: 'today' }, { type: 'upcoming' }];
    const areaSelections = lastMeta.areas.map((area) => ({ type: 'area', id: area.id }) as ThingsSelection);
    const projectSelections = lastMeta.projects.map(
      (project) => ({ type: 'project', id: project.id }) as ThingsSelection
    );
    const allSelections = [...baseSelections, ...areaSelections, ...projectSelections];
    allSelections.forEach((selection) => {
      if (isSameSelection(selection, current)) return;
      void loadSelection(selection, { silent: true, notify: false });
    });
  };

  const selectionKey = (selection: ThingsSelection) => {
    if (selection.type === 'area' || selection.type === 'project') {
      return `${selection.type}:${selection.id}`;
    }
    return selection.type;
  };

  const tasksCacheKey = (selection: ThingsSelection) => `things.tasks.${selectionKey(selection)}`;

  const loadSelection = async (
    selection: ThingsSelection,
    options?: { force?: boolean; silent?: boolean; notify?: boolean }
  ) => {
    const force = options?.force ?? false;
    const silent = options?.silent ?? false;
    const notify = options?.notify ?? true;
    const token = ++loadToken;
    const key = tasksCacheKey(selection);
    const cachedTasks = getCachedData<ThingsTask[]>(key, { ttl: CACHE_TTL, version: CACHE_VERSION });
    const cachedCounts = getCachedData<ThingsCountsResponse | Record<string, number>>(COUNTS_CACHE_KEY, {
      ttl: CACHE_TTL,
      version: CACHE_VERSION
    });
    const cachedToday =
      selection.type === 'today'
        ? cachedTasks
        : getCachedData<ThingsTask[]>(tasksCacheKey({ type: 'today' }), {
            ttl: CACHE_TTL,
            version: CACHE_VERSION
          });
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
    if (cachedCounts) {
      const normalized = normalizeCountsCache(cachedCounts);
      update((state) => ({
        ...state,
        counts: normalized.map,
        todayCount: normalized.todayCount
      }));
    }
    if (cachedToday) {
      update((state) => ({
        ...state,
        todayCount: cachedToday.length
      }));
    }
    if (!force && cachedTasks) {
      const cachedCount = selectionCount(selection, cachedTasks, cachedMeta?.projects ?? []);
      update((state) => ({
        ...state,
        selection,
        tasks: cachedTasks,
        isLoading: false,
        error: '',
        counts: {
          ...state.counts,
          [selectionKey(selection)]: cachedCount
        }
      }));
      if (!isCacheStale(key, CACHE_TTL)) {
        return;
      }
    } else {
      update((state) => ({
        ...state,
        selection,
        isLoading: silent ? state.isLoading : true,
        error: ''
      }));
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
      if (!silent) {
        applyResponse(response, selection);
      } else {
        const cached = getCachedData<ThingsTask[]>(key, { ttl: CACHE_TTL, version: CACHE_VERSION });
        const changed = !cached || JSON.stringify(cached) !== JSON.stringify(response.tasks ?? []);
        if (changed) {
          applyResponse(response, selection);
          if (notify) {
            setSyncNotice('Tasks updated in Things');
          }
        }
      }
      if (!silent) {
        preloadAllSelections(selection);
      }
    } catch (error) {
      if (token !== loadToken) return;
      if (!silent) {
        update((state) => ({
          ...state,
          error: error instanceof Error ? error.message : 'Failed to load Things data'
        }));
      }
    } finally {
      if (token !== loadToken) return;
      if (!silent) {
        update((state) => ({ ...state, isLoading: false }));
      }
    }
  };

  return {
    subscribe,
    reset: () => set(defaultState),
    load: (selection: ThingsSelection, options?: { force?: boolean; silent?: boolean; notify?: boolean }) =>
      loadSelection(selection, options),
    loadCounts: async (force: boolean = false) => {
      const cached = getCachedData<ThingsCountsResponse | Record<string, number>>(COUNTS_CACHE_KEY, {
        ttl: CACHE_TTL,
        version: CACHE_VERSION
      });
      if (cached) {
        const normalized = normalizeCountsCache(cached);
        update((state) => ({
          ...state,
          counts: normalized.map,
          todayCount: normalized.todayCount
        }));
        if (!force && !isCacheStale(COUNTS_CACHE_KEY, CACHE_TTL)) {
          return;
        }
      } else if (!force && !isCacheStale(COUNTS_CACHE_KEY, CACHE_TTL)) {
        return;
      }
      try {
        const response = await thingsAPI.counts();
        applyCountsResponse(response);
      } catch (error) {
        update((state) => ({
          ...state,
          error: error instanceof Error ? error.message : 'Failed to load Things counts'
        }));
      }
    },
    loadDiagnostics: async () => {
      try {
        const response = await thingsAPI.diagnostics();
        update((state) => ({ ...state, diagnostics: response }));
      } catch (error) {
        update((state) => ({
          ...state,
          diagnostics: {
            dbAccess: false,
            dbPath: null,
            dbError: error instanceof Error ? error.message : 'Failed to load diagnostics'
          }
        }));
      }
    },
    completeTask: async (taskId: string) => {
      await thingsAPI.apply({ op: 'complete', id: taskId });
      update((state) => {
        const nextTasks = state.tasks.filter((task) => task.id !== taskId);
        const key = selectionKey(state.selection);
        setCachedData(tasksCacheKey(state.selection), nextTasks, {
          ttl: CACHE_TTL,
          version: CACHE_VERSION
        });
        const nextCounts = {
          ...state.counts,
          [key]: nextTasks.length
        };
        const cachedCounts = getCachedData<ThingsCountsResponse>(COUNTS_CACHE_KEY, {
          ttl: CACHE_TTL,
          version: CACHE_VERSION
        });
        if (cachedCounts) {
          const updatedCounts = { ...cachedCounts };
          if (key === 'today') {
            updatedCounts.counts.today = nextTasks.length;
          } else if (key === 'inbox') {
            updatedCounts.counts.inbox = nextTasks.length;
          } else if (key === 'upcoming') {
            updatedCounts.counts.upcoming = nextTasks.length;
          } else if (key.startsWith('area:')) {
            const areaId = key.split(':')[1];
            updatedCounts.areas = updatedCounts.areas.map((area) =>
              area.id === areaId ? { ...area, count: nextTasks.length } : area
            );
          } else if (key.startsWith('project:')) {
            const projectId = key.split(':')[1];
            updatedCounts.projects = updatedCounts.projects.map((project) =>
              project.id === projectId ? { ...project, count: nextTasks.length } : project
            );
          }
          setCachedData(COUNTS_CACHE_KEY, updatedCounts, { ttl: CACHE_TTL, version: CACHE_VERSION });
        }
        return {
          ...state,
          tasks: nextTasks,
          counts: nextCounts,
          todayCount: state.selection.type === 'today' ? nextTasks.length : state.todayCount
        };
      });
    }
  };
}

export const thingsStore = createThingsStore();
