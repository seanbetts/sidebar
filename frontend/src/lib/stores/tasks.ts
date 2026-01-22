import { get, writable } from 'svelte/store';
import { tasksAPI } from '$lib/services/api';
import {
	classifyDueBucket,
	normalizeDateKey,
	offsetDateKey,
	todayKey
} from '$lib/stores/tasks-utils';
import { getCachedData, isCacheStale, setCachedData } from '$lib/utils/cache';
import type {
	Task,
	TaskArea,
	TaskCountsResponse,
	TaskListResponse,
	TaskProject
} from '$lib/types/tasks';

export type TaskSelection =
	| { type: 'inbox' }
	| { type: 'today' }
	| { type: 'upcoming' }
	| { type: 'area'; id: string }
	| { type: 'project'; id: string }
	| { type: 'search'; query: string };

export type TaskNewTaskDraft = {
	title: string;
	notes: string;
	dueDate: string;
	selection: TaskSelection;
	listId?: string;
	listName?: string;
	areaId?: string;
	projectId?: string;
};

export type TasksState = {
	selection: TaskSelection;
	tasks: Task[];
	areas: TaskArea[];
	projects: TaskProject[];
	todayCount: number;
	counts: Record<string, number>;
	syncNotice: string;
	isLoading: boolean;
	searchPending: boolean;
	newTaskDraft: TaskNewTaskDraft | null;
	newTaskSaving: boolean;
	newTaskError: string;
	error: string;
};

type TasksMetaCache = {
	areas: TaskArea[];
	projects: TaskProject[];
};

const CACHE_TTL = 60 * 1000;
const CACHE_VERSION = '1.0';
const META_CACHE_KEY = 'tasks.meta';
const COUNTS_CACHE_KEY = 'tasks.counts';

const defaultState: TasksState = {
	selection: { type: 'today' },
	tasks: [],
	areas: [],
	projects: [],
	todayCount: 0,
	counts: {},
	syncNotice: '',
	isLoading: false,
	searchPending: false,
	newTaskDraft: null,
	newTaskSaving: false,
	newTaskError: '',
	error: ''
};

function createTasksStore() {
	const { subscribe, set, update } = writable<TasksState>(defaultState);
	let loadToken = 0;
	let hasPreloaded = false;
	let lastMeta: TasksMetaCache = { areas: [], projects: [] };
	let lastNonSearchSelection: TaskSelection = { type: 'today' };
	let syncNoticeTimer: ReturnType<typeof setTimeout> | null = null;
	let searchInFlight: Promise<void> | null = null;
	let pendingSearchQuery: string | null = null;
	const selectionInFlight = new Map<string, Promise<void>>();

	const setSyncNotice = (message: string) => {
		if (syncNoticeTimer) {
			clearTimeout(syncNoticeTimer);
		}
		update((state) => ({ ...state, syncNotice: message }));
		syncNoticeTimer = setTimeout(() => {
			update((state) => ({ ...state, syncNotice: '' }));
		}, 6000);
	};

	const selectionCount = (selection: TaskSelection, tasks: Task[], projects: TaskProject[]) => {
		if (selection.type !== 'area') return tasks.length;
		const projectIds = new Set(projects.map((project) => project.id));
		return tasks.filter((task) => !projectIds.has(task.id) && task.status !== 'project').length;
	};

	const toCountsMap = (counts: TaskCountsResponse): Record<string, number> => {
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

	const isCountsResponse = (
		cached: TaskCountsResponse | Record<string, number>
	): cached is TaskCountsResponse =>
		typeof (cached as TaskCountsResponse).counts === 'object' &&
		Array.isArray((cached as TaskCountsResponse).areas) &&
		Array.isArray((cached as TaskCountsResponse).projects);

	const normalizeCountsCache = (
		cached: TaskCountsResponse | Record<string, number>
	): { map: Record<string, number>; todayCount: number } => {
		if (isCountsResponse(cached)) {
			const map = toCountsMap(cached);
			return { map, todayCount: cached.counts.today ?? 0 };
		}
		const todayCount = cached.today ?? cached.inbox ?? 0;
		return { map: cached, todayCount };
	};

	const applyCountsResponse = (counts: TaskCountsResponse) => {
		const map = toCountsMap(counts);
		update((state) => ({
			...state,
			counts: map,
			todayCount: counts.counts.today
		}));
		setCachedData(COUNTS_CACHE_KEY, counts, { ttl: CACHE_TTL, version: CACHE_VERSION });
	};

	const applyResponse = (response: TaskListResponse, selection: TaskSelection) => {
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
			todayCount: response.scope === 'today' ? (response.tasks ?? []).length : state.todayCount,
			counts: {
				...state.counts,
				[key]: selectionCount(selection, response.tasks ?? [], response.projects ?? state.projects)
			},
			error: ''
		}));
	};

	const applyMetaCountsOnly = (response: TaskListResponse, selection: TaskSelection) => {
		const key = selectionKey(selection);
		lastMeta = {
			areas: response.areas ?? lastMeta.areas,
			projects: response.projects ?? lastMeta.projects
		};
		const taskCount = selectionCount(
			selection,
			response.tasks ?? [],
			response.projects ?? lastMeta.projects
		);
		update((state) => ({
			...state,
			areas: response.areas ?? state.areas,
			projects: response.projects ?? state.projects,
			todayCount: response.scope === 'today' ? (response.tasks ?? []).length : state.todayCount,
			counts: {
				...state.counts,
				[key]: taskCount
			}
		}));
	};

	const isSameSelection = (a: TaskSelection, b: TaskSelection) => {
		if (a.type !== b.type) return false;
		if (a.type === 'area' || a.type === 'project') {
			return a.id === (b as { id: string }).id;
		}
		if (a.type === 'search') {
			return a.query === (b as { query: string }).query;
		}
		return true;
	};

	const preloadAllSelections = (current: TaskSelection) => {
		if (hasPreloaded) return;
		hasPreloaded = true;
		const baseSelections: TaskSelection[] = [{ type: 'today' }, { type: 'upcoming' }];
		const allSelections = baseSelections.filter(
			(selection) => !isSameSelection(selection, current)
		);
		void (async () => {
			for (const selection of allSelections) {
				await loadSelection(selection, { silent: true, notify: false });
				await new Promise((resolve) => setTimeout(resolve, 50));
			}
		})();
	};

	const selectionKey = (selection: TaskSelection) => {
		if (selection.type === 'area' || selection.type === 'project') {
			return `${selection.type}:${selection.id}`;
		}
		if (selection.type === 'search') {
			return `search:${selection.query.toLowerCase()}`;
		}
		return selection.type;
	};

	const tasksCacheKey = (selection: TaskSelection) => `tasks.tasks.${selectionKey(selection)}`;

	const updateTaskCaches = (taskId: string, task: Task, dueDate: string) => {
		const todayKey = tasksCacheKey({ type: 'today' });
		const upcomingKey = tasksCacheKey({ type: 'upcoming' });
		const todayTasks =
			getCachedData<Task[]>(todayKey, { ttl: CACHE_TTL, version: CACHE_VERSION }) ?? [];
		const upcomingTasks =
			getCachedData<Task[]>(upcomingKey, { ttl: CACHE_TTL, version: CACHE_VERSION }) ?? [];
		const targetBucket = classifyDueBucket(dueDate);

		const nextToday = todayTasks.filter((item) => item.id !== taskId);
		const nextUpcoming = upcomingTasks.filter((item) => item.id !== taskId);

		if (targetBucket === 'today') {
			nextToday.unshift(task);
		} else {
			nextUpcoming.unshift(task);
		}

		setCachedData(todayKey, nextToday, { ttl: CACHE_TTL, version: CACHE_VERSION });
		setCachedData(upcomingKey, nextUpcoming, { ttl: CACHE_TTL, version: CACHE_VERSION });

		update((state) => {
			let nextTasks = state.tasks;
			const selectionType = state.selection.type;
			if (selectionType === 'today') {
				nextTasks = nextToday;
			} else if (selectionType === 'upcoming') {
				nextTasks = nextUpcoming;
			} else if (state.selection.type === 'area' || state.selection.type === 'project') {
				nextTasks = state.tasks.filter((item) => item.id !== taskId);
			}
			const nextCounts = {
				...state.counts,
				today: nextToday.length,
				upcoming: nextUpcoming.length
			};
			return {
				...state,
				tasks: nextTasks,
				counts: nextCounts,
				todayCount: nextToday.length
			};
		});

		const cachedCounts = getCachedData<TaskCountsResponse>(COUNTS_CACHE_KEY, {
			ttl: CACHE_TTL,
			version: CACHE_VERSION
		});
		if (cachedCounts) {
			const updatedCounts = { ...cachedCounts };
			updatedCounts.counts.today = nextToday.length;
			updatedCounts.counts.upcoming = nextUpcoming.length;
			setCachedData(COUNTS_CACHE_KEY, updatedCounts, { ttl: CACHE_TTL, version: CACHE_VERSION });
		}
	};

	const loadSelection = async (
		selection: TaskSelection,
		options?: { force?: boolean; silent?: boolean; notify?: boolean }
	) => {
		if (selection.type !== 'search') {
			lastNonSearchSelection = selection;
		}
		const force = options?.force ?? false;
		const silent = options?.silent ?? false;
		const notify = options?.notify ?? true;
		const currentState = get({ subscribe });
		const isCurrent = isSameSelection(selection, currentState.selection);
		let silentFetch = silent;
		let notifyFetch = notify;
		let usesToken = false;
		let token = loadToken;
		const key = tasksCacheKey(selection);
		const cachedTasks = getCachedData<Task[]>(key, {
			ttl: CACHE_TTL,
			version: CACHE_VERSION
		});
		const cachedCounts = getCachedData<TaskCountsResponse | Record<string, number>>(
			COUNTS_CACHE_KEY,
			{
				ttl: CACHE_TTL,
				version: CACHE_VERSION
			}
		);
		const cachedToday =
			selection.type === 'today'
				? cachedTasks
				: getCachedData<Task[]>(tasksCacheKey({ type: 'today' }), {
						ttl: CACHE_TTL,
						version: CACHE_VERSION
					});
		const cachedMeta = getCachedData<TasksMetaCache>(META_CACHE_KEY, {
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
			const showSearchLoading = selection.type === 'search' && cachedTasks.length === 0 && !silent;
			if (!silent || isCurrent) {
				update((state) => ({
					...state,
					selection,
					tasks: cachedTasks,
					isLoading: showSearchLoading ? true : false,
					searchPending: showSearchLoading ? true : state.searchPending,
					error: '',
					counts: {
						...state.counts,
						[selectionKey(selection)]: cachedCount
					}
				}));
			} else {
				update((state) => ({
					...state,
					counts: {
						...state.counts,
						[selectionKey(selection)]: cachedCount
					}
				}));
			}
			if (!isCacheStale(key, CACHE_TTL)) {
				silentFetch = true;
				notifyFetch = false;
			}
		} else {
			if (!silentFetch || isCurrent) {
				const clearTasks = selection.type === 'search';
				update((state) => ({
					...state,
					selection,
					tasks: clearTasks ? [] : state.tasks,
					isLoading: silentFetch ? state.isLoading : true,
					searchPending: selection.type === 'search' ? true : state.searchPending,
					error: ''
				}));
			}
		}
		const inFlight = selectionInFlight.get(key);
		if (inFlight && !force) {
			await inFlight;
			return;
		}
		usesToken = !silentFetch || isCurrent;
		token = usesToken ? ++loadToken : loadToken;
		const request = (async () => {
			try {
				let response: TaskListResponse;
				if (
					selection.type === 'today' ||
					selection.type === 'upcoming' ||
					selection.type === 'inbox'
				) {
					response = await tasksAPI.list(selection.type);
				} else if (selection.type === 'area') {
					response = await tasksAPI.areaTasks(selection.id);
				} else if (selection.type === 'project') {
					response = await tasksAPI.projectTasks(selection.id);
				} else {
					response = await tasksAPI.search(selection.query);
				}
				if (usesToken && token !== loadToken) return;
				setCachedData(key, response.tasks ?? [], { ttl: CACHE_TTL, version: CACHE_VERSION });
				if (response.areas && response.projects) {
					setCachedData(
						META_CACHE_KEY,
						{ areas: response.areas ?? [], projects: response.projects ?? [] },
						{ ttl: CACHE_TTL, version: CACHE_VERSION }
					);
				}
				const latestSelection = get({ subscribe }).selection;
				const stillCurrent = isSameSelection(selection, latestSelection);
				if (!silentFetch || stillCurrent) {
					applyResponse(response, selection);
				} else {
					const cached = getCachedData<Task[]>(key, {
						ttl: CACHE_TTL,
						version: CACHE_VERSION
					});
					const changed =
						!cached || JSON.stringify(cached) !== JSON.stringify(response.tasks ?? []);
					if (changed) {
						applyMetaCountsOnly(response, selection);
						if (notifyFetch) {
							setSyncNotice('Tasks updated');
						}
					}
				}
				if (!silentFetch) {
					preloadAllSelections(selection);
				}
			} catch (error) {
				if (usesToken && token !== loadToken) return;
				if (!silent) {
					update((state) => ({
						...state,
						error: error instanceof Error ? error.message : 'Failed to load tasks data'
					}));
				}
			} finally {
				const isStale = usesToken && token !== loadToken;
				if (!isStale && !silent) {
					update((state) => ({
						...state,
						isLoading: false,
						searchPending: selection.type === 'search' ? false : state.searchPending
					}));
				}
			}
		})();

		selectionInFlight.set(key, request);
		try {
			await request;
		} finally {
			if (selectionInFlight.get(key) === request) {
				selectionInFlight.delete(key);
			}
		}
	};

	return {
		subscribe,
		reset: () => set(defaultState),
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
				await tasksAPI.apply({
					op: 'add',
					title,
					notes: payload.notes?.trim() ?? '',
					due_date: payload.dueDate ?? draft.dueDate,
					list_id: listId,
					list_name: listName
				});
				const stateAfter = get({ subscribe });
				const dueDate = payload.dueDate ?? draft.dueDate;
				const project = listId ? stateAfter.projects.find((item) => item.id === listId) : undefined;
				const area =
					listId && !project ? stateAfter.areas.find((item) => item.id === listId) : undefined;
				const optimisticTask: Task = {
					id: `temp-${Date.now()}`,
					title,
					status: 'open',
					deadlineStart: dueDate,
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
			} catch (error) {
				update((current) => ({
					...current,
					newTaskSaving: false,
					newTaskError: error instanceof Error ? error.message : 'Failed to add task'
				}));
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
				return loadSelection(lastNonSearchSelection);
			}
			pendingSearchQuery = trimmed;
			if (searchInFlight) {
				return searchInFlight;
			}
			searchInFlight = (async () => {
				while (pendingSearchQuery) {
					const nextQuery = pendingSearchQuery;
					pendingSearchQuery = null;
					await loadSelection({ type: 'search', query: nextQuery }, { force: true });
				}
			})().finally(() => {
				searchInFlight = null;
			});
			return searchInFlight;
		},
		clearSearch: () => loadSelection(lastNonSearchSelection),
		completeTask: async (taskId: string) => {
			await tasksAPI.apply({ op: 'complete', id: taskId });
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
				await tasksAPI.apply({ op: 'rename', id: taskId, title: nextTitle });
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
			await tasksAPI.apply({ op: 'notes', id: taskId, notes });
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
		},
		moveTask: async (taskId: string, listId: string, listName?: string) => {
			await tasksAPI.apply({ op: 'move', id: taskId, list_id: listId, list_name: listName });
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
		},
		trashTask: async (taskId: string) => {
			await tasksAPI.apply({ op: 'trash', id: taskId });
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
		},
		setDueDate: async (taskId: string, dueDate: string, op: 'set_due' | 'defer' = 'set_due') => {
			const nextOp = op === 'set_due' ? 'defer' : op;
			await tasksAPI.apply({ op: nextOp, id: taskId, due_date: dueDate });
			const state = get({ subscribe });
			const currentTask = state.tasks.find((task) => task.id === taskId);
			if (currentTask) {
				const updatedTask: Task = {
					...currentTask,
					deadlineStart: dueDate
				};
				updateTaskCaches(taskId, updatedTask, dueDate);
			}
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
		}
	};
}

export const tasksStore = createTasksStore();
