import type { Task, TaskCountsResponse, TaskListResponse, TaskSelection } from '$lib/types/tasks';
import type { TasksMetaCache } from '$lib/stores/tasks-sync';

type StoreState = {
	selection: TaskSelection;
	tasks: Task[];
	areas: unknown[];
	projects: unknown[];
	isLoading: boolean;
	searchPending: boolean;
	error: string;
	counts: Record<string, number>;
	todayCount: number;
};

type LoaderDeps = {
	tasksAPI: {
		list: (scope: string) => Promise<TaskListResponse>;
		areaTasks: (id: string) => Promise<TaskListResponse>;
		projectTasks: (id: string) => Promise<TaskListResponse>;
		search: (query: string) => Promise<TaskListResponse>;
	};
	getState: () => StoreState;
	updateState: (updater: (state: StoreState) => StoreState) => void;
	getCachedData: <T>(key: string, config: { ttl: number; version: string }) => T | null;
	setCachedData: <T>(key: string, data: T, config: { ttl: number; version: string }) => void;
	isCacheStale: (key: string, ttl: number) => boolean;
	cacheTtl: number;
	cacheVersion: string;
	metaCacheKey: string;
	countsCacheKey: string;
	snapshotLoader: { load: () => Promise<{ tasks: Task[]; areas: any[]; projects: any[] } | null> };
	filterTasksForSelection: (tasks: Task[], selection: TaskSelection) => Task[];
	normalizeCountsCache: (cached: TaskCountsResponse | Record<string, number>) => {
		map: Record<string, number>;
		todayCount: number;
	};
	selectionCount: (selection: TaskSelection, tasks: Task[], projects: any[]) => number;
	selectionKey: (selection: TaskSelection) => string;
	tasksCacheKey: (selection: TaskSelection) => string;
	isSameSelection: (a: TaskSelection, b: TaskSelection) => boolean;
	cacheTaskListResponse: (response: TaskListResponse) => Promise<void>;
	setSyncNotice: (message: string) => void;
	applyTaskListResponse: (options: {
		response: TaskListResponse;
		selection: TaskSelection;
		lastMeta: TasksMetaCache;
		setMeta: (meta: TasksMetaCache) => void;
		updateState: LoaderDeps['updateState'];
	}) => void;
	applyTaskMetaCountsOnly: (options: {
		response: TaskListResponse;
		selection: TaskSelection;
		lastMeta: TasksMetaCache;
		setMeta: (meta: TasksMetaCache) => void;
		updateState: LoaderDeps['updateState'];
	}) => void;
	getLastMeta: () => TasksMetaCache;
	setLastMeta: (meta: TasksMetaCache) => void;
	setLastNonSearchSelection: (selection: TaskSelection) => void;
	isBrowser: boolean;
};

export const createTaskLoader = (deps: LoaderDeps) => {
	let loadToken = 0;
	const selectionInFlight = new Map<string, Promise<void>>();
	let preloadAllSelections: (current: TaskSelection) => void = () => {};

	const setPreloadAllSelections = (fn: (current: TaskSelection) => void) => {
		preloadAllSelections = fn;
	};

	const loadSelection = async (
		selection: TaskSelection,
		options?: { force?: boolean; silent?: boolean; notify?: boolean }
	) => {
		if (selection.type !== 'search') {
			deps.setLastNonSearchSelection(selection);
		}
		const force = options?.force ?? false;
		const silent = options?.silent ?? false;
		const notify = options?.notify ?? true;
		const currentState = deps.getState();
		const isCurrent = deps.isSameSelection(selection, currentState.selection);
		let silentFetch = silent;
		let notifyFetch = notify;
		let usesToken = false;
		let token = loadToken;
		const key = deps.tasksCacheKey(selection);
		const cachedTasks = deps.getCachedData<Task[]>(key, {
			ttl: deps.cacheTtl,
			version: deps.cacheVersion
		});
		const cachedCounts = deps.getCachedData<TaskCountsResponse | Record<string, number>>(
			deps.countsCacheKey,
			{
				ttl: deps.cacheTtl,
				version: deps.cacheVersion
			}
		);
		const cachedToday =
			selection.type === 'today'
				? cachedTasks
				: deps.getCachedData<Task[]>(deps.tasksCacheKey({ type: 'today' }), {
						ttl: deps.cacheTtl,
						version: deps.cacheVersion
					});
		const cachedMeta = deps.getCachedData<TasksMetaCache>(deps.metaCacheKey, {
			ttl: deps.cacheTtl,
			version: deps.cacheVersion
		});
		if (cachedMeta) {
			deps.updateState((state) => ({
				...state,
				areas: cachedMeta.areas,
				projects: cachedMeta.projects
			}));
		}
		if (cachedCounts) {
			const normalized = deps.normalizeCountsCache(cachedCounts);
			deps.updateState((state) => ({
				...state,
				counts: normalized.map,
				todayCount: normalized.todayCount
			}));
		}
		if (cachedToday) {
			deps.updateState((state) => ({
				...state,
				todayCount: cachedToday.length
			}));
		}
		if (!force && cachedTasks) {
			const cachedCount = deps.selectionCount(selection, cachedTasks, cachedMeta?.projects ?? []);
			const showSearchLoading = selection.type === 'search' && cachedTasks.length === 0 && !silent;
			if (!silent || isCurrent) {
				deps.updateState((state) => ({
					...state,
					selection,
					tasks: cachedTasks,
					isLoading: showSearchLoading ? true : false,
					searchPending: showSearchLoading ? true : state.searchPending,
					error: '',
					counts: {
						...state.counts,
						[deps.selectionKey(selection)]: cachedCount
					}
				}));
			} else {
				deps.updateState((state) => ({
					...state,
					counts: {
						...state.counts,
						[deps.selectionKey(selection)]: cachedCount
					}
				}));
			}
			if (!deps.isCacheStale(key, deps.cacheTtl)) {
				silentFetch = true;
				notifyFetch = false;
			}
		} else {
			if (!silentFetch || isCurrent) {
				const clearTasks = selection.type === 'search';
				deps.updateState((state) => ({
					...state,
					selection,
					tasks: clearTasks ? [] : state.tasks,
					isLoading: silentFetch ? state.isLoading : true,
					searchPending: selection.type === 'search' ? true : state.searchPending,
					error: ''
				}));
			}
		}
		if (!cachedTasks) {
			void (async () => {
				const snapshot = await deps.snapshotLoader.load();
				if (!snapshot) return;
				const selectionTasks = deps.filterTasksForSelection(snapshot.tasks, selection);
				const latestSelection = deps.getState().selection;
				if (!deps.isSameSelection(selection, latestSelection)) return;
				deps.setCachedData(key, selectionTasks, { ttl: deps.cacheTtl, version: deps.cacheVersion });
				if (snapshot.areas.length || snapshot.projects.length) {
					deps.setCachedData(
						deps.metaCacheKey,
						{ areas: snapshot.areas, projects: snapshot.projects },
						{ ttl: deps.cacheTtl, version: deps.cacheVersion }
					);
				}
				deps.updateState((state) => {
					if (!deps.isSameSelection(selection, state.selection)) return state;
					if (state.tasks.length > 0) return state;
					if (!state.isLoading && !state.error) return state;
					const nextAreas = snapshot.areas.length ? snapshot.areas : state.areas;
					const nextProjects = snapshot.projects.length ? snapshot.projects : state.projects;
					return {
						...state,
						tasks: selectionTasks,
						areas: nextAreas,
						projects: nextProjects,
						todayCount: selection.type === 'today' ? selectionTasks.length : state.todayCount,
						counts: {
							...state.counts,
							[deps.selectionKey(selection)]: deps.selectionCount(
								selection,
								selectionTasks,
								nextProjects
							)
						}
					};
				});
			})();
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
					response = await deps.tasksAPI.list(selection.type);
				} else if (selection.type === 'area') {
					response = await deps.tasksAPI.areaTasks(selection.id);
				} else if (selection.type === 'project') {
					response = await deps.tasksAPI.projectTasks(selection.id);
				} else {
					response = await deps.tasksAPI.search(selection.query);
				}
				if (usesToken && token !== loadToken) return;
				deps.setCachedData(key, response.tasks ?? [], {
					ttl: deps.cacheTtl,
					version: deps.cacheVersion
				});
				if (response.areas && response.projects) {
					deps.setCachedData(
						deps.metaCacheKey,
						{ areas: response.areas ?? [], projects: response.projects ?? [] },
						{ ttl: deps.cacheTtl, version: deps.cacheVersion }
					);
				}
				void deps.cacheTaskListResponse(response);
				const latestSelection = deps.getState().selection;
				const stillCurrent = deps.isSameSelection(selection, latestSelection);
				if (!silentFetch || stillCurrent) {
					deps.applyTaskListResponse({
						response,
						selection,
						lastMeta: deps.getLastMeta(),
						setMeta: deps.setLastMeta,
						updateState: deps.updateState
					});
				} else {
					const cached = deps.getCachedData<Task[]>(key, {
						ttl: deps.cacheTtl,
						version: deps.cacheVersion
					});
					const changed =
						!cached || JSON.stringify(cached) !== JSON.stringify(response.tasks ?? []);
					if (changed) {
						deps.applyTaskMetaCountsOnly({
							response,
							selection,
							lastMeta: deps.getLastMeta(),
							setMeta: deps.setLastMeta,
							updateState: deps.updateState
						});
						if (notifyFetch) {
							deps.setSyncNotice('Tasks updated');
						}
					}
				}
				if (!silentFetch) {
					preloadAllSelections(selection);
				}
			} catch (error) {
				if (usesToken && token !== loadToken) return;
				if (deps.isBrowser && !navigator.onLine && cachedTasks) {
					deps.setSyncNotice('Offline - showing cached tasks');
				}
				if (!silent) {
					deps.updateState((state) => ({
						...state,
						error: error instanceof Error ? error.message : 'Failed to load tasks data'
					}));
				}
			} finally {
				const isStale = usesToken && token !== loadToken;
				if (!isStale && !silent) {
					deps.updateState((state) => ({
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

	return { loadSelection, setPreloadAllSelections };
};
