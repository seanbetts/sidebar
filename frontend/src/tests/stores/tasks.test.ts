import { beforeEach, describe, expect, it, vi } from 'vitest';
import { get } from 'svelte/store';
import { tasksStore } from '$lib/stores/tasks';

const cacheState = new Map<string, unknown>();

const { tasksAPI } = vi.hoisted(() => ({
	tasksAPI: {
		list: vi.fn(),
		counts: vi.fn(),
		search: vi.fn(),
		createGroup: vi.fn(),
		createProject: vi.fn()
	}
}));

vi.mock('$lib/services/api', () => ({
	tasksAPI
}));

const { taskSync } = vi.hoisted(() => ({
	taskSync: {
		cacheTaskListResponse: vi.fn(),
		enqueueTaskOperation: vi.fn().mockResolvedValue(null),
		flushTaskOutbox: vi.fn().mockResolvedValue(null),
		hydrateTaskCache: vi.fn().mockResolvedValue({
			tasks: [],
			projects: [],
			groups: [],
			lastSync: null
		})
	}
}));

vi.mock('$lib/services/task_sync', () => taskSync);

const { taskCache } = vi.hoisted(() => ({
	taskCache: {
		loadTaskCacheSnapshot: vi.fn().mockResolvedValue({
			tasks: [],
			projects: [],
			groups: [],
			lastSync: null
		})
	}
}));

vi.mock('$lib/stores/task_cache', () => taskCache);

vi.mock('$lib/utils/cache', () => ({
	getCachedData: vi.fn((key: string) => cacheState.get(key) ?? null),
	setCachedData: vi.fn((key: string, value: unknown) => cacheState.set(key, value)),
	isCacheStale: vi.fn(() => false)
}));

vi.mock('svelte-sonner', () => ({
	toast: { message: vi.fn() }
}));

describe('tasksStore', () => {
	beforeEach(() => {
		cacheState.clear();
		vi.clearAllMocks();
		tasksStore.reset();
	});

	it('starts a new task draft with Home as default list', async () => {
		tasksAPI.list.mockResolvedValue({
			scope: 'today',
			tasks: [],
			groups: [{ id: 'home', title: 'Home' }],
			projects: []
		});

		await tasksStore.load({ type: 'today' }, { force: true });
		tasksStore.startNewTask();

		const state = get(tasksStore);
		expect(state.newTaskDraft?.listId).toBe('home');
		expect(state.newTaskDraft?.dueDate).toMatch(/^\d{4}-\d{2}-\d{2}/);
	});

	it('requires a list and title when creating a task', async () => {
		tasksStore.startNewTask();

		await tasksStore.createTask({ title: 'New task' });

		const state = get(tasksStore);
		expect(state.newTaskError).toBe('Select a project or group.');
	});

	it('requires a title when creating a task with a list', async () => {
		tasksAPI.list.mockResolvedValue({
			scope: 'today',
			tasks: [],
			groups: [{ id: 'home', title: 'Home' }],
			projects: []
		});

		await tasksStore.load({ type: 'today' }, { force: true });
		tasksStore.startNewTask();

		await tasksStore.createTask({ title: '   ' });

		const state = get(tasksStore);
		expect(state.newTaskError).toBe('Title is required.');
	});

	it('creates task groups and refreshes data', async () => {
		tasksAPI.list.mockResolvedValue({
			scope: 'today',
			tasks: [],
			groups: [],
			projects: []
		});
		tasksAPI.counts.mockResolvedValue({
			counts: { inbox: 0, today: 0, upcoming: 0 },
			groups: [],
			projects: []
		});
		tasksAPI.createGroup.mockResolvedValue({ id: 'group-1', title: 'Work' });

		await tasksStore.load({ type: 'today' }, { force: true });
		await tasksStore.createGroup('Work');

		expect(tasksAPI.createGroup).toHaveBeenCalledWith('Work');
		expect(tasksAPI.list).toHaveBeenCalledWith('today');
		expect(tasksAPI.counts).toHaveBeenCalled();
	});

	it('creates task projects and refreshes data', async () => {
		tasksAPI.list.mockResolvedValue({
			scope: 'today',
			tasks: [],
			groups: [],
			projects: []
		});
		tasksAPI.counts.mockResolvedValue({
			counts: { inbox: 0, today: 0, upcoming: 0 },
			groups: [],
			projects: []
		});
		tasksAPI.createProject.mockResolvedValue({
			id: 'project-1',
			title: 'Launch',
			groupId: 'group-1',
			status: 'active'
		});

		await tasksStore.load({ type: 'today' }, { force: true });
		await tasksStore.createProject('Launch', 'group-1');

		expect(tasksAPI.createProject).toHaveBeenCalledWith('Launch', 'group-1');
		expect(tasksAPI.list).toHaveBeenCalledWith('today');
		expect(tasksAPI.counts).toHaveBeenCalled();
	});

	it('loads cached counts without calling the API', async () => {
		cacheState.set('tasks.counts', {
			counts: { inbox: 1, today: 2, upcoming: 3 },
			groups: [],
			projects: []
		});

		await tasksStore.loadCounts();

		const state = get(tasksStore);
		expect(state.todayCount).toBe(2);
		expect(state.counts.today).toBe(2);
		expect(tasksAPI.counts).not.toHaveBeenCalled();
	});

	it('hydrates from cached snapshot when list cache is empty', async () => {
		taskCache.loadTaskCacheSnapshot.mockResolvedValue({
			tasks: [
				{
					id: 'task-9',
					title: 'Cached',
					status: 'inbox',
					groupId: null,
					projectId: null
				}
			],
			projects: [],
			groups: [],
			lastSync: null
		});
		tasksAPI.list.mockRejectedValue(new Error('Offline'));

		await tasksStore.load({ type: 'inbox' }, { force: true });
		await new Promise((resolve) => setTimeout(resolve, 10));

		const state = get(tasksStore);
		expect(state.tasks[0].title).toBe('Cached');
	});

	it('removes completed tasks and updates counts', async () => {
		tasksAPI.list.mockResolvedValue({
			scope: 'today',
			tasks: [{ id: 'task-1', title: 'Task', status: 'open', groupId: null, projectId: null }],
			groups: [],
			projects: []
		});
		cacheState.set('tasks.counts', {
			counts: { inbox: 0, today: 1, upcoming: 0 },
			groups: [],
			projects: []
		});

		await tasksStore.load({ type: 'today' }, { force: true });
		await tasksStore.completeTask('task-1');

		const state = get(tasksStore);
		expect(state.tasks).toHaveLength(0);
		expect(state.counts.today).toBe(0);
	});

	it('renames tasks optimistically', async () => {
		cacheState.set('tasks.tasks.today', [
			{ id: 'task-2', title: 'Old', status: 'open', groupId: null, projectId: null }
		]);
		tasksAPI.list.mockResolvedValue({
			scope: 'today',
			tasks: [{ id: 'task-2', title: 'Old', status: 'open', groupId: null, projectId: null }],
			groups: [],
			projects: []
		});
		taskSync.enqueueTaskOperation.mockResolvedValue(null);

		await tasksStore.load({ type: 'today' });
		await tasksStore.renameTask('task-2', 'New');

		const state = get(tasksStore);
		expect(state.tasks[0].title).toBe('New');
		expect(taskSync.enqueueTaskOperation).toHaveBeenCalledWith({
			op: 'rename',
			id: 'task-2',
			title: 'New'
		});
	});

	it('requires a title when renaming a task', async () => {
		tasksAPI.list.mockResolvedValue({
			scope: 'today',
			tasks: [{ id: 'task-7', title: 'Task', status: 'open', groupId: null, projectId: null }],
			groups: [],
			projects: []
		});

		await tasksStore.load({ type: 'today' }, { force: true });
		await tasksStore.renameTask('task-7', '   ');

		const state = get(tasksStore);
		expect(state.error).toBe('Title is required');
	});

	it('moves tasks between today and upcoming caches', async () => {
		const task = { id: 'task-3', title: 'Task', status: 'open', groupId: null, projectId: null };
		cacheState.set('tasks.tasks.today', [task]);
		cacheState.set('tasks.tasks.upcoming', []);
		cacheState.set('tasks.counts', {
			counts: { inbox: 0, today: 1, upcoming: 0 },
			groups: [],
			projects: []
		});
		tasksAPI.list.mockResolvedValue({
			scope: 'today',
			tasks: [],
			groups: [],
			projects: []
		});
		tasksAPI.counts.mockResolvedValue({
			counts: { inbox: 0, today: 0, upcoming: 1 },
			groups: [],
			projects: []
		});

		await tasksStore.load({ type: 'today' });
		await tasksStore.setDueDate('task-3', '2099-01-01');

		const state = get(tasksStore);
		expect(state.tasks).toHaveLength(0);
		expect(state.counts.today).toBe(0);
	});

	it('sets an offline notice when moving a task without browser connectivity', async () => {
		const originalNavigator = globalThis.navigator;
		vi.stubGlobal('navigator', { onLine: false });
		tasksAPI.list.mockResolvedValue({
			scope: 'today',
			tasks: [],
			groups: [],
			projects: []
		});
		taskSync.enqueueTaskOperation.mockResolvedValue(null);

		await tasksStore.load({ type: 'today' }, { force: true });
		await tasksStore.moveTask('task-8', 'group-1', 'Home');

		const state = get(tasksStore);
		expect(state.syncNotice).toBe('Task moved offline');
		vi.stubGlobal('navigator', originalNavigator);
	});

	it('sets an error when moving a task fails', async () => {
		tasksAPI.list.mockResolvedValue({
			scope: 'today',
			tasks: [],
			groups: [],
			projects: []
		});
		taskSync.enqueueTaskOperation.mockRejectedValueOnce(new Error('Move failed'));

		await tasksStore.load({ type: 'today' }, { force: true });
		await tasksStore.moveTask('task-9', 'group-1');

		const state = get(tasksStore);
		expect(state.error).toBe('Move failed');
	});

	it('replaces repeating tasks with the next instance on completion', async () => {
		const today = new Date().toISOString().slice(0, 10);
		tasksAPI.list.mockResolvedValue({
			scope: 'today',
			tasks: [
				{
					id: 'task-10',
					title: 'Repeat',
					status: 'open',
					deadline: today,
					repeating: true,
					groupId: null,
					projectId: null
				}
			],
			groups: [],
			projects: []
		});
		taskSync.enqueueTaskOperation.mockResolvedValue({
			nextTasks: [
				{
					id: 'task-11',
					title: 'Repeat',
					status: 'open',
					deadline: today,
					repeating: true,
					groupId: null,
					projectId: null
				}
			]
		});

		await tasksStore.load({ type: 'today' }, { force: true });
		await tasksStore.completeTask('task-10');

		const state = get(tasksStore);
		expect(state.tasks).toHaveLength(1);
		expect(state.tasks[0].id).toBe('task-11');
	});

	it('updates notes locally after applying', async () => {
		tasksAPI.list.mockResolvedValue({
			scope: 'today',
			tasks: [
				{ id: 'task-4', title: 'Note', status: 'open', notes: '', groupId: null, projectId: null }
			],
			groups: [],
			projects: []
		});
		taskSync.enqueueTaskOperation.mockResolvedValue(null);

		await tasksStore.load({ type: 'today' }, { force: true });
		await tasksStore.updateNotes('task-4', 'Details');

		const state = get(tasksStore);
		expect(state.tasks[0].notes).toBe('Details');
	});

	it('trashes tasks and updates counts', async () => {
		tasksAPI.list.mockResolvedValue({
			scope: 'today',
			tasks: [{ id: 'task-5', title: 'Trash', status: 'open', groupId: null, projectId: null }],
			groups: [],
			projects: []
		});
		taskSync.enqueueTaskOperation.mockResolvedValue(null);

		await tasksStore.load({ type: 'today' }, { force: true });
		await tasksStore.trashTask('task-5');

		const state = get(tasksStore);
		expect(state.tasks).toHaveLength(0);
		expect(state.counts.today).toBe(0);
	});

	it('debounces search requests', async () => {
		vi.useFakeTimers();
		tasksAPI.search.mockResolvedValue({ scope: 'search', tasks: [], groups: [], projects: [] });

		tasksStore.search('First');
		tasksStore.search('Second');

		expect(tasksAPI.search).not.toHaveBeenCalled();
		await vi.advanceTimersByTimeAsync(300);

		expect(tasksAPI.search).toHaveBeenCalledTimes(1);
		expect(tasksAPI.search).toHaveBeenCalledWith('Second');
		vi.useRealTimers();
	});
});
