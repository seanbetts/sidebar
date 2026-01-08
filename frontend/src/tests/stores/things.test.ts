import { beforeEach, describe, expect, it, vi } from 'vitest';
import { get } from 'svelte/store';
import { thingsStore } from '$lib/stores/things';

const cacheState = new Map<string, unknown>();

const { thingsAPI } = vi.hoisted(() => ({
	thingsAPI: {
		list: vi.fn(),
		counts: vi.fn(),
		diagnostics: vi.fn(),
		apply: vi.fn()
	}
}));

vi.mock('$lib/services/api', () => ({
	thingsAPI
}));

vi.mock('$lib/utils/cache', () => ({
	getCachedData: vi.fn((key: string) => cacheState.get(key) ?? null),
	setCachedData: vi.fn((key: string, value: unknown) => cacheState.set(key, value)),
	isCacheStale: vi.fn(() => false)
}));

describe('thingsStore', () => {
	beforeEach(() => {
		cacheState.clear();
		vi.clearAllMocks();
		thingsStore.reset();
	});

	it('starts a new task draft with Home as default list', async () => {
		thingsAPI.list.mockResolvedValue({
			scope: 'today',
			tasks: [],
			areas: [{ id: 'home', title: 'Home' }],
			projects: []
		});

		await thingsStore.load({ type: 'today' }, { force: true });
		thingsStore.startNewTask();

		const state = get(thingsStore);
		expect(state.newTaskDraft?.listId).toBe('home');
		expect(state.newTaskDraft?.dueDate).toMatch(/^\d{4}-\d{2}-\d{2}/);
	});

	it('requires a list and title when creating a task', async () => {
		thingsStore.startNewTask();

		await thingsStore.createTask({ title: 'New task' });

		const state = get(thingsStore);
		expect(state.newTaskError).toBe('Select a project or area.');
	});

	it('loads cached counts without calling the API', async () => {
		cacheState.set('things.counts', {
			counts: { inbox: 1, today: 2, upcoming: 3 },
			areas: [],
			projects: []
		});

		await thingsStore.loadCounts();

		const state = get(thingsStore);
		expect(state.todayCount).toBe(2);
		expect(state.counts.today).toBe(2);
		expect(thingsAPI.counts).not.toHaveBeenCalled();
	});

	it('stores diagnostics error when the bridge call fails', async () => {
		thingsAPI.diagnostics.mockRejectedValue(new Error('No bridge'));

		await thingsStore.loadDiagnostics();

		const state = get(thingsStore);
		expect(state.diagnostics?.dbAccess).toBe(false);
		expect(state.diagnostics?.dbError).toBe('No bridge');
	});

	it('removes completed tasks and updates counts', async () => {
		thingsAPI.list.mockResolvedValue({
			scope: 'today',
			tasks: [{ id: 'task-1', title: 'Task', status: 'open', areaId: null, projectId: null }],
			areas: [],
			projects: []
		});
		thingsAPI.apply.mockResolvedValue(undefined);
		cacheState.set('things.counts', {
			counts: { inbox: 0, today: 1, upcoming: 0 },
			areas: [],
			projects: []
		});

		await thingsStore.load({ type: 'today' }, { force: true });
		await thingsStore.completeTask('task-1');

		const state = get(thingsStore);
		expect(state.tasks).toHaveLength(0);
		expect(state.counts.today).toBe(0);
	});

	it('renames tasks optimistically', async () => {
		cacheState.set('things.tasks.today', [
			{ id: 'task-2', title: 'Old', status: 'open', areaId: null, projectId: null }
		]);
		thingsAPI.list.mockResolvedValue({
			scope: 'today',
			tasks: [{ id: 'task-2', title: 'Old', status: 'open', areaId: null, projectId: null }],
			areas: [],
			projects: []
		});
		thingsAPI.apply.mockResolvedValue(undefined);

		await thingsStore.load({ type: 'today' });
		await thingsStore.renameTask('task-2', 'New');

		const state = get(thingsStore);
		expect(state.tasks[0].title).toBe('New');
		expect(thingsAPI.apply).toHaveBeenCalledWith({ op: 'rename', id: 'task-2', title: 'New' });
	});

	it('moves tasks between today and upcoming caches', async () => {
		const task = { id: 'task-3', title: 'Task', status: 'open', areaId: null, projectId: null };
		cacheState.set('things.tasks.today', [task]);
		cacheState.set('things.tasks.upcoming', []);
		cacheState.set('things.counts', {
			counts: { inbox: 0, today: 1, upcoming: 0 },
			areas: [],
			projects: []
		});
		thingsAPI.list.mockResolvedValue({
			scope: 'today',
			tasks: [],
			areas: [],
			projects: []
		});
		thingsAPI.apply.mockResolvedValue(undefined);
		thingsAPI.counts.mockResolvedValue({
			counts: { inbox: 0, today: 0, upcoming: 1 },
			areas: [],
			projects: []
		});

		await thingsStore.load({ type: 'today' });
		await thingsStore.setDueDate('task-3', '2099-01-01');

		const state = get(thingsStore);
		expect(state.tasks).toHaveLength(0);
		expect(state.counts.today).toBe(0);
	});

	it('updates notes locally after applying', async () => {
		thingsAPI.list.mockResolvedValue({
			scope: 'today',
			tasks: [
				{ id: 'task-4', title: 'Note', status: 'open', notes: '', areaId: null, projectId: null }
			],
			areas: [],
			projects: []
		});
		thingsAPI.apply.mockResolvedValue(undefined);

		await thingsStore.load({ type: 'today' }, { force: true });
		await thingsStore.updateNotes('task-4', 'Details');

		const state = get(thingsStore);
		expect(state.tasks[0].notes).toBe('Details');
	});

	it('trashes tasks and updates counts', async () => {
		thingsAPI.list.mockResolvedValue({
			scope: 'today',
			tasks: [{ id: 'task-5', title: 'Trash', status: 'open', areaId: null, projectId: null }],
			areas: [],
			projects: []
		});
		thingsAPI.apply.mockResolvedValue(undefined);

		await thingsStore.load({ type: 'today' }, { force: true });
		await thingsStore.trashTask('task-5');

		const state = get(thingsStore);
		expect(state.tasks).toHaveLength(0);
		expect(state.counts.today).toBe(0);
	});
});
