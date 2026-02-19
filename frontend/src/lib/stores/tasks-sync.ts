import { flushTaskOutbox, hydrateTaskCache } from '$lib/services/task_sync';
import { setCachedData } from '$lib/utils/cache';
import type {
	Task,
	TaskGroup,
	TaskProject,
	TaskSyncConflict,
	TaskSelection,
	TaskSyncResponse,
	TaskSyncUpdates
} from '$lib/types/tasks';

type TaskStateLike = {
	selection: TaskSelection;
	tasks: Task[];
	groups: TaskGroup[];
	projects: TaskProject[];
};

export type TasksMetaCache = {
	groups: TaskGroup[];
	projects: TaskProject[];
};

type SyncCoordinatorOptions<TState extends TaskStateLike> = {
	cacheTtl: number;
	cacheVersion: string;
	isBrowser: boolean;
	tasksCacheKey: (selection: TaskSelection) => string;
	updateState: (updater: (state: TState) => TState) => void;
	setMeta: (meta: TasksMetaCache) => void;
	setSyncNotice: (message: string) => void;
	setConflictNotice: (message: string) => void;
	onNextTasks?: (tasks: Task[]) => void;
};

type TaskSyncResponseLike = Partial<Omit<TaskSyncResponse, 'updates' | 'conflicts'>> & {
	updates?: Partial<TaskSyncUpdates>;
	conflicts?: Array<Partial<TaskSyncConflict>>;
};

const mergeById = <T extends { id: string }>(existing: T[], updates: T[]) => {
	if (!updates.length) return existing;
	const map = new Map(existing.map((item) => [item.id, item]));
	updates.forEach((item) => {
		map.set(item.id, { ...map.get(item.id), ...item });
	});
	return Array.from(map.values());
};

const mergeUpdatesIntoState = <TState extends TaskStateLike>(
	updates: TaskSyncUpdates,
	options: Pick<
		SyncCoordinatorOptions<TState>,
		'cacheTtl' | 'cacheVersion' | 'tasksCacheKey' | 'updateState' | 'setMeta'
	>
) => {
	if (!updates.tasks?.length && !updates.projects?.length && !updates.groups?.length) {
		return;
	}
	options.updateState((state) => {
		const nextGroups = updates.groups?.length
			? mergeById(state.groups, updates.groups)
			: state.groups;
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
		options.setMeta({ groups: nextGroups, projects: nextProjects });
		return {
			...state,
			tasks: nextTasks,
			groups: nextGroups,
			projects: nextProjects
		};
	});
};

/**
 * Create sync helpers that update task store state.
 */
export function createTasksSyncCoordinator<TState extends TaskStateLike>(
	options: SyncCoordinatorOptions<TState>
) {
	let initialized = false;

	const handleSyncResponse = (response: TaskSyncResponseLike | null) => {
		if (!response) return;
		if (response.nextTasks?.length) {
			options.onNextTasks?.(response.nextTasks);
		}
		if (response.conflicts?.length) {
			options.setConflictNotice('Tasks changed elsewhere. Refresh to continue.');
		}
		if (response.updates) {
			mergeUpdatesIntoState(
				{
					tasks: response.updates.tasks ?? [],
					projects: response.updates.projects ?? [],
					groups: response.updates.groups ?? []
				},
				options
			);
		}
	};

	const initialize = () => {
		if (!options.isBrowser || initialized) return;
		initialized = true;
		void hydrateTaskCache().then((snapshot) => {
			if (!snapshot) return;
			options.updateState((state) => {
				if (state.groups.length || state.projects.length) {
					return state;
				}
				options.setMeta({ groups: snapshot.groups, projects: snapshot.projects });
				return { ...state, groups: snapshot.groups, projects: snapshot.projects };
			});
		});
		window.addEventListener('online', () => {
			void flushTaskOutbox().then(handleSyncResponse);
		});
		void flushTaskOutbox().then(handleSyncResponse);
	};

	return { handleSyncResponse, initialize };
}
