import type {
	Task,
	TaskArea,
	TaskCountsResponse,
	TaskListResponse,
	TaskProject,
	TaskSelection
} from '$lib/types/tasks';

type NormalizeCountsResult = {
	map: Record<string, number>;
	todayCount: number;
};

type UpdateTaskCachesOptions = {
	taskId: string;
	task: Task;
	targetBucket: 'today' | 'upcoming';
	cacheTtl: number;
	cacheVersion: string;
	countsCacheKey: string;
	getCachedData: <T>(key: string, config: { ttl: number; version: string }) => T | null;
	setCachedData: <T>(key: string, data: T, config: { ttl: number; version: string }) => void;
	updateState: (
		updater: (state: {
			tasks: Task[];
			selection: TaskSelection;
			counts: Record<string, number>;
			todayCount: number;
		}) => {
			tasks: Task[];
			selection: TaskSelection;
			counts: Record<string, number>;
			todayCount: number;
		}
	) => void;
};

type ApplyResponseOptions = {
	response: TaskListResponse;
	selection: TaskSelection;
	lastMeta: { areas: TaskArea[]; projects: TaskProject[] };
	setMeta: (meta: { areas: TaskArea[]; projects: TaskProject[] }) => void;
	updateState: (
		updater: (state: {
			tasks: Task[];
			areas: TaskArea[];
			projects: TaskProject[];
			todayCount: number;
			counts: Record<string, number>;
			error?: string;
		}) => {
			tasks: Task[];
			areas: TaskArea[];
			projects: TaskProject[];
			todayCount: number;
			counts: Record<string, number>;
			error?: string;
		}
	) => void;
};

/**
 * Build a cache key for a task selection.
 */
export const selectionKey = (selection: TaskSelection): string => {
	if (selection.type === 'area' || selection.type === 'project') {
		return `${selection.type}:${selection.id}`;
	}
	if (selection.type === 'search') {
		return `search:${selection.query.toLowerCase()}`;
	}
	return selection.type;
};

/**
 * Build a cache key for a task list.
 */
export const tasksCacheKey = (selection: TaskSelection): string =>
	`tasks.tasks.${selectionKey(selection)}`;

/**
 * Compute counts for the current selection.
 */
export const selectionCount = (
	selection: TaskSelection,
	tasks: Task[],
	projects: TaskProject[]
): number => {
	if (selection.type !== 'area') return tasks.length;
	const projectIds = new Set(projects.map((project) => project.id));
	return tasks.filter((task) => !projectIds.has(task.id) && task.status !== 'project').length;
};

/**
 * Compare two task selections for equality.
 */
export const isSameSelection = (a: TaskSelection, b: TaskSelection): boolean => {
	if (a.type !== b.type) return false;
	if (a.type === 'area' || a.type === 'project') {
		return a.id === (b as { id: string }).id;
	}
	if (a.type === 'search') {
		return a.query === (b as { query: string }).query;
	}
	return true;
};

/**
 * Create a preload helper for background task list hydration.
 */
export const createPreloadAllSelections = (
	loadSelection: (
		selection: TaskSelection,
		options?: { force?: boolean; silent?: boolean; notify?: boolean }
	) => Promise<void>
) => {
	let hasPreloaded = false;
	return (current: TaskSelection) => {
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
};

/**
 * Normalize cached task counts to a consistent shape.
 */
export const normalizeCountsCache = (
	cached: TaskCountsResponse | Record<string, number>
): NormalizeCountsResult => {
	const isCountsResponse =
		typeof (cached as TaskCountsResponse).counts === 'object' &&
		Array.isArray((cached as TaskCountsResponse).areas) &&
		Array.isArray((cached as TaskCountsResponse).projects);
	if (isCountsResponse) {
		return { map: buildCountsMap(cached), todayCount: cached.counts.today ?? 0 };
	}
	const todayCount = cached.today ?? cached.inbox ?? 0;
	return { map: cached, todayCount };
};

/**
 * Build a counts map from a counts response payload.
 */
export const buildCountsMap = (counts: TaskCountsResponse): Record<string, number> => {
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

/**
 * Update today/upcoming caches after changing a task due date.
 */
export const updateTaskCaches = (options: UpdateTaskCachesOptions): void => {
	const todayKey = tasksCacheKey({ type: 'today' });
	const upcomingKey = tasksCacheKey({ type: 'upcoming' });
	const todayTasks =
		options.getCachedData<Task[]>(todayKey, {
			ttl: options.cacheTtl,
			version: options.cacheVersion
		}) ?? [];
	const upcomingTasks =
		options.getCachedData<Task[]>(upcomingKey, {
			ttl: options.cacheTtl,
			version: options.cacheVersion
		}) ?? [];

	const nextToday = todayTasks.filter((item) => item.id !== options.taskId);
	const nextUpcoming = upcomingTasks.filter((item) => item.id !== options.taskId);

	if (options.targetBucket === 'today') {
		nextToday.unshift(options.task);
	} else {
		nextUpcoming.unshift(options.task);
	}

	options.setCachedData(todayKey, nextToday, {
		ttl: options.cacheTtl,
		version: options.cacheVersion
	});
	options.setCachedData(upcomingKey, nextUpcoming, {
		ttl: options.cacheTtl,
		version: options.cacheVersion
	});

	options.updateState((state) => {
		let nextTasks = state.tasks;
		if (state.selection.type === 'today') {
			nextTasks = nextToday;
		} else if (state.selection.type === 'upcoming') {
			nextTasks = nextUpcoming;
		} else if (state.selection.type === 'area' || state.selection.type === 'project') {
			nextTasks = state.tasks.filter((item) => item.id !== options.taskId);
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

	const cachedCounts = options.getCachedData<TaskCountsResponse>(options.countsCacheKey, {
		ttl: options.cacheTtl,
		version: options.cacheVersion
	});
	if (cachedCounts) {
		const updatedCounts = { ...cachedCounts };
		updatedCounts.counts.today = nextToday.length;
		updatedCounts.counts.upcoming = nextUpcoming.length;
		options.setCachedData(options.countsCacheKey, updatedCounts, {
			ttl: options.cacheTtl,
			version: options.cacheVersion
		});
	}
};

/**
 * Apply a task list response to store state.
 */
export const applyTaskListResponse = (options: ApplyResponseOptions): void => {
	const meta = {
		areas: options.response.areas ?? options.lastMeta.areas,
		projects: options.response.projects ?? options.lastMeta.projects
	};
	options.setMeta(meta);
	options.updateState((state) => ({
		...state,
		tasks: options.response.tasks ?? [],
		areas: options.response.areas ?? state.areas,
		projects: options.response.projects ?? state.projects,
		todayCount:
			options.response.scope === 'today' ? (options.response.tasks ?? []).length : state.todayCount,
		counts: {
			...state.counts,
			[selectionKey(options.selection)]: selectionCount(
				options.selection,
				options.response.tasks ?? [],
				options.response.projects ?? state.projects
			)
		},
		error: ''
	}));
};

/**
 * Apply metadata and counts without updating the current task list.
 */
export const applyTaskMetaCountsOnly = (options: ApplyResponseOptions): void => {
	const meta = {
		areas: options.response.areas ?? options.lastMeta.areas,
		projects: options.response.projects ?? options.lastMeta.projects
	};
	options.setMeta(meta);
	const taskCount = selectionCount(
		options.selection,
		options.response.tasks ?? [],
		options.response.projects ?? meta.projects
	);
	options.updateState((state) => ({
		...state,
		areas: options.response.areas ?? state.areas,
		projects: options.response.projects ?? state.projects,
		todayCount:
			options.response.scope === 'today' ? (options.response.tasks ?? []).length : state.todayCount,
		counts: {
			...state.counts,
			[selectionKey(options.selection)]: taskCount
		}
	}));
};

const taskDueDate = (task: Task): string | null => task.deadline ?? null;

/**
 * Filter cached tasks for the current selection.
 */
export const filterTasksForSelection = (
	tasks: Task[],
	selection: TaskSelection,
	projects: TaskProject[] = []
): Task[] => {
	const today = new Date();
	today.setHours(0, 0, 0, 0);
	const normalized = tasks.filter(
		(task) => !task.deletedAt && task.status !== 'completed' && task.status !== 'trashed'
	);
	if (selection.type === 'inbox') {
		return normalized.filter((task) => task.status === 'inbox');
	}
	if (selection.type === 'area') {
		const projectAreaById = new Map(
			projects.map((project) => [project.id, project.areaId ?? null])
		);
		return normalized.filter((task) => {
			if (task.areaId === selection.id) return true;
			if (!task.projectId) return false;
			return projectAreaById.get(task.projectId) === selection.id;
		});
	}
	if (selection.type === 'project') {
		return normalized.filter((task) => task.projectId === selection.id);
	}
	if (selection.type === 'search') {
		const query = selection.query.trim().toLowerCase();
		if (!query) return normalized;
		return normalized.filter((task) => {
			const haystack = `${task.title ?? ''} ${task.notes ?? ''}`.toLowerCase();
			return haystack.includes(query);
		});
	}
	const dueTasks = normalized.filter((task) => task.status !== 'someday');
	if (selection.type === 'today') {
		return dueTasks.filter((task) => {
			const due = taskDueDate(task);
			if (!due) return false;
			const dueDate = new Date(`${due.slice(0, 10)}T00:00:00`);
			return dueDate.getTime() <= today.getTime();
		});
	}
	if (selection.type === 'upcoming') {
		return dueTasks.filter((task) => {
			const due = taskDueDate(task);
			if (!due) return false;
			const dueDate = new Date(`${due.slice(0, 10)}T00:00:00`);
			return dueDate.getTime() > today.getTime();
		});
	}
	return normalized;
};
