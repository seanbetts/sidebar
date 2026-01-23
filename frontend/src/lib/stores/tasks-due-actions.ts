import type { Task, TaskSelection } from '$lib/types/tasks';

type UpdateState = (updater: (state: StoreState) => StoreState) => void;

type StoreState = {
	selection: TaskSelection;
	tasks: Task[];
	counts: Record<string, number>;
	todayCount: number;
	error?: string;
};

type CacheConfig = {
	cacheTtl: number;
	cacheVersion: string;
	countsCacheKey: string;
};

type DueActionDeps = {
	update: UpdateState;
	getState: () => StoreState;
	selectionKey: (selection: TaskSelection) => string;
	tasksCacheKey: (selection: TaskSelection) => string;
	updateTaskCaches: (options: {
		taskId: string;
		task: Task;
		targetBucket: 'today' | 'upcoming';
		cacheTtl: number;
		cacheVersion: string;
		countsCacheKey: string;
		getCachedData: <T>(key: string, config: { ttl: number; version: string }) => T | null;
		setCachedData: <T>(key: string, data: T, config: { ttl: number; version: string }) => void;
		updateState: UpdateState;
	}) => void;
	classifyDueBucket: (value: string) => 'today' | 'upcoming';
	getCachedData: <T>(key: string, config: { ttl: number; version: string }) => T | null;
	setCachedData: <T>(key: string, data: T, config: { ttl: number; version: string }) => void;
	enqueueTaskOperation: (operation: Record<string, unknown>) => Promise<any>;
	handleSyncResponse: (response: any) => void;
	loadSelection: (
		selection: TaskSelection,
		options?: { force?: boolean; silent?: boolean; notify?: boolean }
	) => Promise<void>;
	applyCountsResponse: (response: any) => void;
	setSyncNotice: (message: string) => void;
	isBrowser: boolean;
	tasksAPI: { counts: () => Promise<any> };
	cacheConfig: CacheConfig;
};

const refreshTaskLists = async (deps: DueActionDeps, selection: TaskSelection) => {
	if (!deps.isBrowser || !navigator.onLine) {
		return;
	}
	void deps.loadSelection(selection, { force: true, silent: true, notify: false });
	if (selection.type !== 'today') {
		void deps.loadSelection({ type: 'today' }, { force: true, silent: true, notify: false });
	}
	if (selection.type !== 'upcoming') {
		void deps.loadSelection({ type: 'upcoming' }, { force: true, silent: true, notify: false });
	}
	void deps.tasksAPI
		.counts()
		.then(deps.applyCountsResponse)
		.catch(() => {
			deps.update((current) => ({
				...current,
				error: 'Failed to update task counts'
			}));
		});
};

export const createDueActions = (deps: DueActionDeps) => {
	const { cacheTtl, cacheVersion, countsCacheKey } = deps.cacheConfig;

	const setRepeat = async (
		taskId: string,
		rule: Task['recurrenceRule'] | null,
		startDate: string | null
	) => {
		const state = deps.getState();
		const currentTask = state.tasks.find((task) => task.id === taskId);
		const dueDate = startDate ?? currentTask?.deadline ?? null;
		if (currentTask) {
			const updatedTask: Task = {
				...currentTask,
				repeating: Boolean(rule),
				recurrenceRule: rule ?? null,
				deadline: dueDate ?? currentTask.deadline
			};
			if (dueDate) {
				deps.updateTaskCaches({
					taskId,
					task: updatedTask,
					targetBucket: deps.classifyDueBucket(dueDate),
					cacheTtl,
					cacheVersion,
					countsCacheKey,
					getCachedData: deps.getCachedData,
					setCachedData: deps.setCachedData,
					updateState: deps.update
				});
			} else {
				deps.update((current) => {
					const nextTasks = current.tasks.map((task) => (task.id === taskId ? updatedTask : task));
					deps.setCachedData(deps.tasksCacheKey(current.selection), nextTasks, {
						ttl: cacheTtl,
						version: cacheVersion
					});
					return { ...current, tasks: nextTasks };
				});
			}
		}
		try {
			const response = await deps.enqueueTaskOperation({
				op: 'set_repeat',
				id: taskId,
				recurrence_rule: rule,
				start_date: dueDate
			});
			deps.handleSyncResponse(response);
			if (deps.isBrowser && navigator.onLine) {
				await refreshTaskLists(deps, state.selection);
			} else {
				deps.setSyncNotice('Task updated offline');
			}
		} catch (error) {
			deps.update((current) => ({
				...current,
				error: error instanceof Error ? error.message : 'Failed to update repeat rule'
			}));
		}
	};

	const clearDueDate = async (taskId: string) => {
		const state = deps.getState();
		const currentTask = state.tasks.find((task) => task.id === taskId);
		if (currentTask) {
			deps.update((current) => {
				let nextTasks = current.tasks.map((task) =>
					task.id === taskId ? { ...task, deadline: null } : task
				);
				if (current.selection.type === 'today' || current.selection.type === 'upcoming') {
					nextTasks = nextTasks.filter((task) => task.id !== taskId);
				}
				deps.setCachedData(deps.tasksCacheKey(current.selection), nextTasks, {
					ttl: cacheTtl,
					version: cacheVersion
				});
				const nextCounts = {
					...current.counts,
					[deps.selectionKey(current.selection)]: nextTasks.length
				};
				return {
					...current,
					tasks: nextTasks,
					counts: nextCounts,
					todayCount: current.selection.type === 'today' ? nextTasks.length : current.todayCount
				};
			});
		}
		try {
			const response = await deps.enqueueTaskOperation({ op: 'clear_due', id: taskId });
			deps.handleSyncResponse(response);
			if (deps.isBrowser && navigator.onLine) {
				await refreshTaskLists(deps, state.selection);
			} else {
				deps.setSyncNotice('Task updated offline');
			}
		} catch (error) {
			deps.update((current) => ({
				...current,
				error: error instanceof Error ? error.message : 'Failed to clear due date'
			}));
		}
	};

	const setDueDate = async (
		taskId: string,
		dueDate: string,
		op: 'set_due' | 'defer' = 'set_due'
	) => {
		const nextOp = op === 'set_due' ? 'defer' : op;
		const state = deps.getState();
		const currentTask = state.tasks.find((task) => task.id === taskId);
		if (currentTask) {
			const updatedTask: Task = {
				...currentTask,
				deadline: dueDate
			};
			deps.updateTaskCaches({
				taskId,
				task: updatedTask,
				targetBucket: deps.classifyDueBucket(dueDate),
				cacheTtl,
				cacheVersion,
				countsCacheKey,
				getCachedData: deps.getCachedData,
				setCachedData: deps.setCachedData,
				updateState: deps.update
			});
		}
		try {
			const response = await deps.enqueueTaskOperation({
				op: nextOp,
				id: taskId,
				due_date: dueDate
			});
			deps.handleSyncResponse(response);
			if (deps.isBrowser && navigator.onLine) {
				await refreshTaskLists(deps, state.selection);
			} else {
				deps.setSyncNotice('Task updated offline');
			}
		} catch (error) {
			deps.update((current) => ({
				...current,
				error: error instanceof Error ? error.message : 'Failed to update due date'
			}));
		}
	};

	return { clearDueDate, setDueDate, setRepeat };
};
