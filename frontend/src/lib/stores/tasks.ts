import { get, writable } from 'svelte/store';
import { tasksAPI } from '$lib/services/api';
import { loadTaskCacheSnapshot } from '$lib/stores/task_cache';
import { cacheTaskListResponse, enqueueTaskOperation } from '$lib/services/task_sync';
import {
	applyTaskListResponse,
	applyTaskMetaCountsOnly,
	buildCountsMap,
	createPreloadAllSelections,
	filterTasksForSelection,
	isSameSelection,
	normalizeCountsCache,
	selectionCount,
	selectionKey,
	tasksCacheKey,
	updateTaskCaches
} from '$lib/stores/tasks-cache-helpers';
import { createCountsApplier, createSnapshotLoader } from '$lib/stores/tasks-store-helpers';
import { createNotice } from '$lib/stores/tasks-notice';
import { createTasksSyncCoordinator, type TasksMetaCache } from '$lib/stores/tasks-sync';
import { createDueActions } from '$lib/stores/tasks-due-actions';
import { createTaskLoader } from '$lib/stores/tasks-loader';
import type { TaskNewTaskDraft, TasksState } from '$lib/stores/tasks-types';
import {
	classifyDueBucket,
	normalizeDateKey,
	offsetDateKey,
	todayKey
} from '$lib/stores/tasks-utils';
import { getCachedData, isCacheStale, setCachedData } from '$lib/utils/cache';
import { toast } from 'svelte-sonner';
import type { Task, TaskCountsResponse, TaskProject, TaskSelection } from '$lib/types/tasks';

export type { TaskSelection } from '$lib/types/tasks';
export type { TaskNewTaskDraft, TasksState } from '$lib/stores/tasks-types';

const CACHE_TTL = 60 * 1000;
const CACHE_VERSION = '1.0';
const META_CACHE_KEY = 'tasks.meta';
const COUNTS_CACHE_KEY = 'tasks.counts';
const isBrowser = typeof window !== 'undefined';

const defaultState: TasksState = {
	selection: { type: 'today' },
	tasks: [],
	areas: [],
	projects: [],
	todayCount: 0,
	counts: {},
	syncNotice: '',
	conflictNotice: '',
	isLoading: false,
	searchPending: false,
	newTaskDraft: null,
	newTaskSaving: false,
	newTaskError: '',
	error: ''
};

function createTasksStore() {
	const { subscribe, set, update } = writable<TasksState>(defaultState);
	let lastMeta: TasksMetaCache = { areas: [], projects: [] };
	let lastNonSearchSelection: TaskSelection = { type: 'today' };
	let searchInFlight: Promise<void> | null = null;
	let pendingSearchQuery: string | null = null;
	let searchDebounceTimer: ReturnType<typeof setTimeout> | null = null;
	const setSyncNotice = createNotice('syncNotice', update);
	const setConflictNotice = createNotice('conflictNotice', update, null);
	const snapshotLoader = createSnapshotLoader(loadTaskCacheSnapshot);
	const applyCountsResponse = createCountsApplier(
		update,
		setCachedData,
		COUNTS_CACHE_KEY,
		{ ttl: CACHE_TTL, version: CACHE_VERSION },
		buildCountsMap
	);
	const clearSearchDebounce = () => {
		if (!searchDebounceTimer) return;
		clearTimeout(searchDebounceTimer);
		searchDebounceTimer = null;
	};

	const { handleSyncResponse, initialize: initializeSync } = createTasksSyncCoordinator({
		cacheTtl: CACHE_TTL,
		cacheVersion: CACHE_VERSION,
		isBrowser,
		tasksCacheKey,
		updateState: update,
		setMeta: (meta) => {
			lastMeta = meta;
		},
		setSyncNotice,
		setConflictNotice,
		onNextTasks: (nextTasks) => {
			if (!nextTasks.length) return;
			if (nextTasks.length === 1) {
				toast.message(`Next instance scheduled: "${nextTasks[0].title}"`);
				return;
			}
			toast.message(`Next instances scheduled: ${nextTasks.length}`);
		}
	});

	const { loadSelection, setPreloadAllSelections } = createTaskLoader({
		tasksAPI,
		getState: () => get({ subscribe }),
		updateState: update,
		getCachedData,
		setCachedData,
		isCacheStale,
		cacheTtl: CACHE_TTL,
		cacheVersion: CACHE_VERSION,
		metaCacheKey: META_CACHE_KEY,
		countsCacheKey: COUNTS_CACHE_KEY,
		snapshotLoader,
		filterTasksForSelection,
		normalizeCountsCache,
		selectionCount,
		selectionKey,
		tasksCacheKey,
		isSameSelection,
		cacheTaskListResponse,
		setSyncNotice,
		applyTaskListResponse,
		applyTaskMetaCountsOnly,
		getLastMeta: () => lastMeta,
		setLastMeta: (meta) => {
			lastMeta = meta;
		},
		setLastNonSearchSelection: (selection) => {
			lastNonSearchSelection = selection;
		},
		isBrowser
	});

	setPreloadAllSelections(createPreloadAllSelections(loadSelection));

	const dueActions = createDueActions({
		update,
		getState: () => get({ subscribe }),
		selectionKey,
		tasksCacheKey,
		updateTaskCaches,
		classifyDueBucket,
		getCachedData,
		setCachedData,
		enqueueTaskOperation,
		handleSyncResponse,
		loadSelection,
		applyCountsResponse,
		setSyncNotice,
		isBrowser,
		tasksAPI,
		cacheConfig: {
			cacheTtl: CACHE_TTL,
			cacheVersion: CACHE_VERSION,
			countsCacheKey: COUNTS_CACHE_KEY
		}
	});

	initializeSync();

	return {
		subscribe,
		reset: () => {
			snapshotLoader.reset();
			pendingSearchQuery = null;
			clearSearchDebounce();
			set(defaultState);
		},
		clearConflictNotice: () => update((state) => ({ ...state, conflictNotice: '' })),
		load: (
			selection: TaskSelection,
			options?: { force?: boolean; silent?: boolean; notify?: boolean }
		) => loadSelection(selection, options),
		startNewTask: () => {
			const state = get({ subscribe });
			const baseSelection =
				state.selection.type === 'search' ? lastNonSearchSelection : state.selection;
			let listId =
				baseSelection.type === 'area' || baseSelection.type === 'project'
					? baseSelection.id
					: undefined;
			const projectId = baseSelection.type === 'project' ? baseSelection.id : undefined;
			let areaId =
				baseSelection.type === 'area'
					? baseSelection.id
					: projectId
						? (state.projects.find((project) => project.id === projectId)?.areaId ?? null)
						: null;
			const dueDate = baseSelection.type === 'upcoming' ? offsetDateKey(1) : todayKey();
			if (!listId) {
				const homeArea = state.areas.find((area) => area.title.toLowerCase() === 'home');
				listId = homeArea?.id;
				areaId = homeArea?.id ?? areaId;
			}
			const listName = listId
				? (state.projects.find((project) => project.id === listId)?.title ??
					state.areas.find((area) => area.id === listId)?.title)
				: undefined;
			const draft: TaskNewTaskDraft = {
				title: '',
				notes: '',
				dueDate,
				selection: baseSelection,
				listId,
				listName,
				areaId: areaId ?? undefined,
				projectId
			};
			update((current) => ({ ...current, newTaskDraft: draft, newTaskError: '' }));
		},
		cancelNewTask: () => update((state) => ({ ...state, newTaskDraft: null, newTaskError: '' })),
		clearNewTaskError: () => update((state) => ({ ...state, newTaskError: '' })),
		createTask: async (payload: {
			title: string;
			notes?: string;
			dueDate?: string;
			listId?: string | null;
			listName?: string | null;
		}) => {
			const state = get({ subscribe });
			const draft = state.newTaskDraft;
			if (!draft) return;
			const title = payload.title.trim();
			const listId = payload.listId ?? draft.listId;
			const listName =
				payload.listName ??
				draft.listName ??
				(listId
					? (state.projects.find((project) => project.id === listId)?.title ??
						state.areas.find((area) => area.id === listId)?.title)
					: undefined);
			if (!listId) {
				update((current) => ({ ...current, newTaskError: 'Select a project or area.' }));
				return;
			}
			if (!title) {
				update((current) => ({ ...current, newTaskError: 'Title is required.' }));
				return;
			}
			update((current) => ({ ...current, newTaskSaving: true, newTaskError: '' }));
			try {
				const stateAfter = get({ subscribe });
				const dueDate = payload.dueDate ?? draft.dueDate;
				const project = listId ? stateAfter.projects.find((item) => item.id === listId) : undefined;
				const area =
					listId && !project ? stateAfter.areas.find((item) => item.id === listId) : undefined;
				const tempId = `temp-${Date.now()}`;
				const optimisticTask: Task = {
					id: tempId,
					title,
					status: 'open',
					deadline: dueDate,
					notes: payload.notes?.trim() ?? '',
					projectId: project?.id ?? null,
					areaId: project?.areaId ?? area?.id ?? null
				};
				update((current) => {
					const selectionKeyValue = selectionKey(draft.selection);
					const nextTasks = isSameSelection(current.selection, draft.selection)
						? [optimisticTask, ...current.tasks]
						: current.tasks;
					setCachedData(tasksCacheKey(draft.selection), nextTasks, {
						ttl: CACHE_TTL,
						version: CACHE_VERSION
					});
					const nextCounts = {
						...current.counts,
						[selectionKeyValue]: (current.counts[selectionKeyValue] ?? 0) + 1
					};
					return {
						...current,
						tasks: nextTasks,
						counts: nextCounts,
						todayCount: current.selection.type === 'today' ? nextTasks.length : current.todayCount,
						newTaskDraft: null,
						newTaskSaving: false,
						newTaskError: ''
					};
				});
				const response = await enqueueTaskOperation({
					op: 'add',
					title,
					notes: payload.notes?.trim() ?? '',
					due_date: dueDate,
					list_id: listId,
					list_name: listName
				});
				if (response?.tasks?.length) {
					const created = response.tasks[0];
					update((current) => {
						const nextTasks = current.tasks.map((task) => (task.id === tempId ? created : task));
						setCachedData(tasksCacheKey(draft.selection), nextTasks, {
							ttl: CACHE_TTL,
							version: CACHE_VERSION
						});
						return { ...current, tasks: nextTasks };
					});
				}
				handleSyncResponse(response);
				if (isBrowser && navigator.onLine) {
					await loadSelection(draft.selection, { force: true, silent: true, notify: false });
					void tasksAPI
						.counts()
						.then(applyCountsResponse)
						.catch(() => {
							update((current) => ({
								...current,
								error: 'Failed to update task counts'
							}));
						});
				} else {
					setSyncNotice('Task saved offline');
				}
			} catch (error) {
				update((current) => ({
					...current,
					newTaskSaving: false,
					newTaskError: error instanceof Error ? error.message : 'Failed to add task'
				}));
			}
		},
		createArea: async (title: string) => {
			const trimmed = title.trim();
			if (!trimmed) return;
			try {
				await tasksAPI.createArea(trimmed);
				const selection = get({ subscribe }).selection;
				await loadSelection(selection, { force: true, silent: true, notify: false });
				void tasksAPI
					.counts()
					.then(applyCountsResponse)
					.catch(() => {
						update((current) => ({
							...current,
							error: 'Failed to update task counts'
						}));
					});
			} catch (error) {
				update((state) => ({
					...state,
					error: error instanceof Error ? error.message : 'Failed to create area'
				}));
				throw error;
			}
		},
		createProject: async (title: string, areaId: string | null) => {
			const trimmed = title.trim();
			if (!trimmed) return;
			try {
				await tasksAPI.createProject(trimmed, areaId);
				const selection = get({ subscribe }).selection;
				await loadSelection(selection, { force: true, silent: true, notify: false });
				void tasksAPI
					.counts()
					.then(applyCountsResponse)
					.catch(() => {
						update((current) => ({
							...current,
							error: 'Failed to update task counts'
						}));
					});
			} catch (error) {
				update((state) => ({
					...state,
					error: error instanceof Error ? error.message : 'Failed to create project'
				}));
				throw error;
			}
		},
		loadCounts: async (force: boolean = false) => {
			const cached = getCachedData<TaskCountsResponse | Record<string, number>>(COUNTS_CACHE_KEY, {
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
				const response = await tasksAPI.counts();
				applyCountsResponse(response);
			} catch (error) {
				update((state) => ({
					...state,
					error: error instanceof Error ? error.message : 'Failed to load task counts'
				}));
			}
		},
		search: (query: string) => {
			const trimmed = query.trim();
			if (!trimmed) {
				pendingSearchQuery = null;
				clearSearchDebounce();
				return loadSelection(lastNonSearchSelection);
			}
			pendingSearchQuery = trimmed;
			if (searchInFlight) {
				return searchInFlight;
			}
			clearSearchDebounce();
			searchDebounceTimer = setTimeout(() => {
				searchDebounceTimer = null;
				searchInFlight = (async () => {
					while (pendingSearchQuery) {
						const nextQuery = pendingSearchQuery;
						pendingSearchQuery = null;
						await loadSelection({ type: 'search', query: nextQuery }, { force: true });
					}
				})().finally(() => {
					searchInFlight = null;
				});
			}, 250);
			return searchInFlight ?? Promise.resolve();
		},
		clearSearch: () => loadSelection(lastNonSearchSelection),
		completeTask: async (taskId: string) => {
			const currentTask = get({ subscribe }).tasks.find((task) => task.id === taskId);
			if (!currentTask?.repeating) {
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
					const cachedCounts = getCachedData<TaskCountsResponse>(COUNTS_CACHE_KEY, {
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
						setCachedData(COUNTS_CACHE_KEY, updatedCounts, {
							ttl: CACHE_TTL,
							version: CACHE_VERSION
						});
					}
					return {
						...state,
						tasks: nextTasks,
						counts: nextCounts,
						todayCount: state.selection.type === 'today' ? nextTasks.length : state.todayCount
					};
				});
			}
			try {
				const response = await enqueueTaskOperation({ op: 'complete', id: taskId });
				handleSyncResponse(response);
				if (currentTask?.repeating && response?.nextTasks?.length) {
					update((state) => {
						const nextTask = response.nextTasks[0];
						const baseTasks = state.tasks.filter((task) => task.id !== taskId);
						const mergedTasks = baseTasks.some((task) => task.id === nextTask.id)
							? baseTasks.map((task) => (task.id === nextTask.id ? nextTask : task))
							: [...baseTasks, nextTask];
						const nextTasks = filterTasksForSelection(mergedTasks, state.selection, state.projects);
						setCachedData(tasksCacheKey(state.selection), nextTasks, {
							ttl: CACHE_TTL,
							version: CACHE_VERSION
						});
						return {
							...state,
							tasks: nextTasks,
							counts: {
								...state.counts,
								[selectionKey(state.selection)]: nextTasks.length
							},
							todayCount: state.selection.type === 'today' ? nextTasks.length : state.todayCount
						};
					});
				}
				if (
					response?.nextTasks?.length &&
					isBrowser &&
					navigator.onLine &&
					!currentTask?.repeating
				) {
					void loadSelection(get({ subscribe }).selection, {
						force: true,
						silent: true,
						notify: false
					});
				}
			} catch (error) {
				update((state) => ({
					...state,
					error: error instanceof Error ? error.message : 'Failed to complete task'
				}));
			}
		},
		renameTask: async (taskId: string, title: string) => {
			const nextTitle = title.trim();
			if (!nextTitle) {
				update((state) => ({ ...state, error: 'Title is required' }));
				return;
			}
			const state = get({ subscribe });
			const originalTask = state.tasks.find((task) => task.id === taskId);
			if (!originalTask) {
				return;
			}
			update((current) => {
				const nextTasks = current.tasks.map((task) =>
					task.id === taskId ? { ...task, title: nextTitle } : task
				);
				setCachedData(tasksCacheKey(current.selection), nextTasks, {
					ttl: CACHE_TTL,
					version: CACHE_VERSION
				});
				return { ...current, tasks: nextTasks };
			});
			try {
				const response = await enqueueTaskOperation({
					op: 'rename',
					id: taskId,
					title: nextTitle
				});
				handleSyncResponse(response);
			} catch (error) {
				update((current) => {
					const nextTasks = current.tasks.map((task) =>
						task.id === taskId ? { ...task, title: originalTask.title } : task
					);
					setCachedData(tasksCacheKey(current.selection), nextTasks, {
						ttl: CACHE_TTL,
						version: CACHE_VERSION
					});
					return {
						...current,
						tasks: nextTasks,
						error: error instanceof Error ? error.message : 'Failed to rename task'
					};
				});
			}
		},
		updateNotes: async (taskId: string, notes: string) => {
			update((state) => {
				const nextTasks = state.tasks.map((task) =>
					task.id === taskId ? { ...task, notes } : task
				);
				setCachedData(tasksCacheKey(state.selection), nextTasks, {
					ttl: CACHE_TTL,
					version: CACHE_VERSION
				});
				return { ...state, tasks: nextTasks };
			});
			try {
				const response = await enqueueTaskOperation({ op: 'notes', id: taskId, notes });
				handleSyncResponse(response);
			} catch (error) {
				update((state) => ({
					...state,
					error: error instanceof Error ? error.message : 'Failed to update task notes'
				}));
			}
		},
		moveTask: async (taskId: string, listId: string, listName?: string) => {
			try {
				const response = await enqueueTaskOperation({
					op: 'move',
					id: taskId,
					list_id: listId,
					list_name: listName
				});
				handleSyncResponse(response);
				if (isBrowser && navigator.onLine) {
					const state = get({ subscribe });
					void loadSelection(state.selection, { force: true, silent: true, notify: false });
					if (state.selection.type !== 'today') {
						void loadSelection({ type: 'today' }, { force: true, silent: true, notify: false });
					}
					if (state.selection.type !== 'upcoming') {
						void loadSelection({ type: 'upcoming' }, { force: true, silent: true, notify: false });
					}
					void tasksAPI
						.counts()
						.then(applyCountsResponse)
						.catch(() => {
							update((current) => ({
								...current,
								error: 'Failed to update task counts'
							}));
						});
				} else {
					setSyncNotice('Task moved offline');
				}
			} catch (error) {
				update((current) => ({
					...current,
					error: error instanceof Error ? error.message : 'Failed to move task'
				}));
			}
		},
		trashTask: async (taskId: string) => {
			update((state) => {
				const nextTasks = state.tasks.filter((task) => task.id !== taskId);
				const key = selectionKey(state.selection);
				setCachedData(tasksCacheKey(state.selection), nextTasks, {
					ttl: CACHE_TTL,
					version: CACHE_VERSION
				});
				const nextCounts = {
					...state.counts,
					[key]: Math.max((state.counts[key] ?? nextTasks.length) - 1, 0)
				};
				return {
					...state,
					tasks: nextTasks,
					counts: nextCounts,
					todayCount: state.selection.type === 'today' ? nextTasks.length : state.todayCount
				};
			});
			try {
				const response = await enqueueTaskOperation({ op: 'trash', id: taskId });
				handleSyncResponse(response);
			} catch (error) {
				update((state) => ({
					...state,
					error: error instanceof Error ? error.message : 'Failed to trash task'
				}));
			}
		},
		setRepeat: dueActions.setRepeat,
		clearDueDate: dueActions.clearDueDate,
		setDueDate: dueActions.setDueDate
	};
}

export const tasksStore = createTasksStore();
