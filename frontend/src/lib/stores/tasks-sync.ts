import { flushTaskOutbox, hydrateTaskCache } from '$lib/services/task_sync';
import { setCachedData } from '$lib/utils/cache';
import type {
	Task,
	TaskArea,
	TaskProject,
	TaskSyncResponse,
	TaskSyncUpdates
} from '$lib/types/tasks';

type TaskSelectionLike = {
	type: string;
	id?: string;
	query?: string;
};

type TaskStateLike = {
	selection: TaskSelectionLike;
	tasks: Task[];
	areas: TaskArea[];
	projects: TaskProject[];
};

export type TasksMetaCache = {
	areas: TaskArea[];
	projects: TaskProject[];
};

type SyncCoordinatorOptions = {
	cacheTtl: number;
	cacheVersion: string;
	isBrowser: boolean;
	tasksCacheKey: (selection: TaskSelectionLike) => string;
	updateState: (updater: (state: TaskStateLike) => TaskStateLike) => void;
	setMeta: (meta: TasksMetaCache) => void;
	setSyncNotice: (message: string) => void;
};

const mergeById = <T extends { id: string }>(existing: T[], updates: T[]) => {
	if (!updates.length) return existing;
	const map = new Map(existing.map((item) => [item.id, item]));
	updates.forEach((item) => {
		map.set(item.id, { ...map.get(item.id), ...item });
	});
	return Array.from(map.values());
};

const mergeUpdatesIntoState = (
	updates: TaskSyncUpdates,
	options: Pick<
		SyncCoordinatorOptions,
		'cacheTtl' | 'cacheVersion' | 'tasksCacheKey' | 'updateState' | 'setMeta'
	>
) => {
	if (!updates.tasks?.length && !updates.projects?.length && !updates.areas?.length) {
		return;
	}
	options.updateState((state) => {
		const nextAreas = updates.areas?.length ? mergeById(state.areas, updates.areas) : state.areas;
		const nextProjects = updates.projects?.length
			? mergeById(state.projects, updates.projects)
			: state.projects;
		const updatesMap = new Map((updates.tasks ?? []).map((task) => [task.id, task]));
		let nextTasks = state.tasks;
		if (updatesMap.size) {
			nextTasks = state.tasks
				.map((task) => (updatesMap.has(task.id) ? { ...task, ...updatesMap.get(task.id) } : task))
				.filter(
					(task) => !task.deletedAt && task.status !== 'trashed' && task.status !== 'completed'
				);
			setCachedData(options.tasksCacheKey(state.selection), nextTasks, {
				ttl: options.cacheTtl,
				version: options.cacheVersion
			});
		}
		options.setMeta({ areas: nextAreas, projects: nextProjects });
		return {
			...state,
			tasks: nextTasks,
			areas: nextAreas,
			projects: nextProjects
		};
	});
};

/**
 * Create sync helpers that update task store state.
 */
export function createTasksSyncCoordinator(options: SyncCoordinatorOptions) {
	let initialized = false;

	const handleSyncResponse = (response: TaskSyncResponse | null) => {
		if (!response) return;
		if (response.conflicts?.length) {
			options.setSyncNotice('Tasks changed elsewhere. Review updates.');
		}
		if (response.updates) {
			mergeUpdatesIntoState(response.updates, options);
		}
	};

	const initialize = () => {
		if (!options.isBrowser || initialized) return;
		initialized = true;
		void hydrateTaskCache().then((snapshot) => {
			if (!snapshot) return;
			options.updateState((state) => {
				if (state.areas.length || state.projects.length) {
					return state;
				}
				options.setMeta({ areas: snapshot.areas, projects: snapshot.projects });
				return { ...state, areas: snapshot.areas, projects: snapshot.projects };
			});
		});
		window.addEventListener('online', () => {
			void flushTaskOutbox().then(handleSyncResponse);
		});
		void flushTaskOutbox().then(handleSyncResponse);
	};

	return { handleSyncResponse, initialize };
}
