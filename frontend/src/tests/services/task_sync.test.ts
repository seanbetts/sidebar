import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Task, TaskGroup, TaskProject } from '$lib/types/tasks';

const { tasksAPI } = vi.hoisted(() => ({
	tasksAPI: {
		sync: vi.fn()
	}
}));

vi.mock('$lib/services/api', () => ({
	tasksAPI
}));

const { taskCache } = vi.hoisted(() => ({
	taskCache: {
		applySyncUpdates: vi.fn(),
		enqueueOperation: vi.fn(),
		getLastSync: vi.fn(),
		getOutboxBatch: vi.fn(),
		loadTaskCacheSnapshot: vi.fn(),
		removeOutboxOperations: vi.fn(),
		setLastSync: vi.fn(),
		upsertGroups: vi.fn(),
		upsertProjects: vi.fn(),
		upsertTasks: vi.fn()
	}
}));

vi.mock('$lib/stores/task_cache', () => taskCache);

const originalNavigator = globalThis.navigator;
const originalCrypto = globalThis.crypto;

const setOnline = (isOnline: boolean) => {
	Object.defineProperty(globalThis, 'navigator', {
		value: { onLine: isOnline },
		configurable: true
	});
};

const loadTaskSyncService = async () => {
	vi.resetModules();
	return import('$lib/services/task_sync');
};

const createTask = (id: string, title: string): Task => ({
	id,
	title,
	status: 'open',
	groupId: null,
	projectId: null
});

const createProject = (id: string, title: string): TaskProject => ({
	id,
	title,
	groupId: null,
	status: 'active'
});

const createGroup = (id: string, title: string): TaskGroup => ({
	id,
	title
});

const createSyncResponse = () => ({
	applied: ['op-1'],
	serverUpdatedSince: '2026-02-17T10:00:00Z',
	updates: { tasks: [], projects: [], groups: [] },
	tasks: [],
	nextTasks: []
});

const createDeferred = <T>() => {
	let resolve!: (value: T) => void;
	let reject!: (reason?: unknown) => void;
	const promise = new Promise<T>((res, rej) => {
		resolve = res;
		reject = rej;
	});
	return { promise, resolve, reject };
};

describe('task_sync service', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		setOnline(true);
		taskCache.applySyncUpdates.mockResolvedValue(undefined);
		taskCache.enqueueOperation.mockResolvedValue(undefined);
		taskCache.getLastSync.mockResolvedValue(null);
		taskCache.getOutboxBatch.mockResolvedValue([]);
		taskCache.loadTaskCacheSnapshot.mockResolvedValue({
			tasks: [],
			projects: [],
			groups: [],
			lastSync: null
		});
		taskCache.removeOutboxOperations.mockResolvedValue(undefined);
		taskCache.setLastSync.mockResolvedValue(undefined);
		taskCache.upsertGroups.mockResolvedValue(undefined);
		taskCache.upsertProjects.mockResolvedValue(undefined);
		taskCache.upsertTasks.mockResolvedValue(undefined);
		tasksAPI.sync.mockResolvedValue(createSyncResponse());
	});

	afterEach(() => {
		Object.defineProperty(globalThis, 'navigator', {
			value: originalNavigator,
			configurable: true
		});
		Object.defineProperty(globalThis, 'crypto', {
			value: originalCrypto,
			configurable: true
		});
	});

	it('hydrates cache from task cache store', async () => {
		const { hydrateTaskCache } = await loadTaskSyncService();
		const snapshot = {
			tasks: [createTask('task-1', 'Task 1')],
			projects: [createProject('project-1', 'Project 1')],
			groups: [createGroup('group-1', 'Group 1')],
			lastSync: '2026-02-17T10:00:00Z'
		};
		taskCache.loadTaskCacheSnapshot.mockResolvedValue(snapshot);

		await expect(hydrateTaskCache()).resolves.toEqual(snapshot);
		expect(taskCache.loadTaskCacheSnapshot).toHaveBeenCalledTimes(1);
	});

	it('caches task list response and defaults missing arrays', async () => {
		const { cacheTaskListResponse } = await loadTaskSyncService();

		await cacheTaskListResponse({
			scope: 'today',
			tasks: []
		});
		await cacheTaskListResponse({
			scope: 'today',
			tasks: [createTask('task-1', 'Task 1')],
			projects: [createProject('project-1', 'Project 1')],
			groups: [createGroup('group-1', 'Group 1')]
		});

		expect(taskCache.upsertTasks).toHaveBeenNthCalledWith(1, []);
		expect(taskCache.upsertProjects).toHaveBeenNthCalledWith(1, []);
		expect(taskCache.upsertGroups).toHaveBeenNthCalledWith(1, []);
		expect(taskCache.upsertTasks).toHaveBeenNthCalledWith(2, [createTask('task-1', 'Task 1')]);
		expect(taskCache.upsertProjects).toHaveBeenNthCalledWith(2, [
			createProject('project-1', 'Project 1')
		]);
		expect(taskCache.upsertGroups).toHaveBeenNthCalledWith(2, [createGroup('group-1', 'Group 1')]);
	});

	it('enqueues operations and skips flush when offline', async () => {
		setOnline(false);
		const { enqueueTaskOperation } = await loadTaskSyncService();

		const response = await enqueueTaskOperation({ op: 'add', title: 'Offline task' });

		expect(response).toBeNull();
		expect(tasksAPI.sync).not.toHaveBeenCalled();
		expect(taskCache.enqueueOperation).toHaveBeenCalledTimes(1);
		const [payload] = taskCache.enqueueOperation.mock.calls[0];
		expect(payload.operation_id).toBeTruthy();
		expect(payload.client_updated_at).toBeTruthy();
	});

	it('prefers crypto.randomUUID for generated operation id', async () => {
		Object.defineProperty(globalThis, 'crypto', {
			value: { randomUUID: vi.fn().mockReturnValue('uuid-from-crypto') },
			configurable: true
		});
		const { enqueueTaskOperation } = await loadTaskSyncService();

		await enqueueTaskOperation({ op: 'add', title: 'Generated id task' });

		const [payload] = taskCache.enqueueOperation.mock.calls[0];
		expect(payload.operation_id).toBe('uuid-from-crypto');
	});

	it('falls back to timestamp-based operation id when crypto is unavailable', async () => {
		Object.defineProperty(globalThis, 'crypto', {
			value: undefined,
			configurable: true
		});
		const { enqueueTaskOperation } = await loadTaskSyncService();

		await enqueueTaskOperation({ op: 'add', title: 'Fallback id task' });

		const [payload] = taskCache.enqueueOperation.mock.calls[0];
		expect(payload.operation_id).toMatch(/^op-/);
	});

	it('keeps provided operation metadata and flushes when online', async () => {
		const { enqueueTaskOperation } = await loadTaskSyncService();
		taskCache.getLastSync.mockResolvedValue('2026-02-17T09:00:00Z');
		taskCache.getOutboxBatch.mockResolvedValue([
			{
				op: 'add',
				id: 'task-1',
				operation_id: 'provided-op',
				client_updated_at: '2026-02-17T09:01:00Z'
			}
		]);

		const response = await enqueueTaskOperation({
			op: 'add',
			id: 'task-1',
			operation_id: 'provided-op',
			client_updated_at: '2026-02-17T09:01:00Z'
		});

		expect(response).toEqual(createSyncResponse());
		expect(taskCache.enqueueOperation).toHaveBeenCalledWith(
			expect.objectContaining({
				operation_id: 'provided-op',
				client_updated_at: '2026-02-17T09:01:00Z'
			})
		);
		expect(tasksAPI.sync).toHaveBeenCalledTimes(1);
	});

	it('returns null on flush when offline', async () => {
		setOnline(false);
		const { flushTaskOutbox } = await loadTaskSyncService();

		await expect(flushTaskOutbox()).resolves.toBeNull();
		expect(taskCache.getLastSync).not.toHaveBeenCalled();
		expect(tasksAPI.sync).not.toHaveBeenCalled();
	});

	it('flushes with empty batch and does not remove operations', async () => {
		const { flushTaskOutbox } = await loadTaskSyncService();
		taskCache.getLastSync.mockResolvedValue('2026-02-17T09:00:00Z');
		taskCache.getOutboxBatch.mockResolvedValue([]);

		await flushTaskOutbox();

		expect(tasksAPI.sync).toHaveBeenCalledWith({
			last_sync: '2026-02-17T09:00:00Z',
			operations: []
		});
		expect(taskCache.removeOutboxOperations).not.toHaveBeenCalled();
		expect(taskCache.applySyncUpdates).toHaveBeenCalledWith({
			tasks: [],
			projects: [],
			groups: []
		});
		expect(taskCache.upsertTasks).toHaveBeenCalledWith([]);
		expect(taskCache.setLastSync).toHaveBeenCalledWith('2026-02-17T10:00:00Z');
	});

	it('flushes queued operations and applies response tasks', async () => {
		const { flushTaskOutbox } = await loadTaskSyncService();
		taskCache.getLastSync.mockResolvedValue('2026-02-17T09:00:00Z');
		taskCache.getOutboxBatch.mockResolvedValue([
			{
				op: 'rename',
				id: 'task-1',
				operation_id: 'op-1',
				client_updated_at: '2026-02-17T09:00:00Z',
				title: 'Updated'
			}
		]);
		tasksAPI.sync.mockResolvedValue({
			applied: ['op-1'],
			serverUpdatedSince: '2026-02-17T10:00:00Z',
			updates: { tasks: [{ id: 'task-2' }], projects: [], groups: [] },
			tasks: [{ id: 'task-1', title: 'Updated' }],
			nextTasks: [{ id: 'task-3', title: 'Next task' }]
		});

		await flushTaskOutbox();

		expect(tasksAPI.sync).toHaveBeenCalledWith({
			last_sync: '2026-02-17T09:00:00Z',
			operations: [
				{
					op: 'rename',
					id: 'task-1',
					operation_id: 'op-1',
					client_updated_at: '2026-02-17T09:00:00Z',
					title: 'Updated'
				}
			]
		});
		expect(taskCache.removeOutboxOperations).toHaveBeenCalledWith(['op-1']);
		expect(taskCache.applySyncUpdates).toHaveBeenCalledWith({
			tasks: [{ id: 'task-2' }],
			projects: [],
			groups: []
		});
		expect(taskCache.upsertTasks).toHaveBeenCalledWith([
			{ id: 'task-1', title: 'Updated' },
			{ id: 'task-3', title: 'Next task' }
		]);
	});

	it('deduplicates concurrent flush calls with the same promise', async () => {
		const { flushTaskOutbox } = await loadTaskSyncService();
		const deferredLastSync = createDeferred<string | null>();
		taskCache.getLastSync.mockReturnValue(deferredLastSync.promise);
		taskCache.getOutboxBatch.mockResolvedValue([]);

		const firstFlush = flushTaskOutbox();
		const secondFlush = flushTaskOutbox();
		await Promise.resolve();
		expect(taskCache.getLastSync).toHaveBeenCalledTimes(1);

		deferredLastSync.resolve(null);
		await expect(firstFlush).resolves.toEqual(createSyncResponse());
		await expect(secondFlush).resolves.toEqual(createSyncResponse());
		expect(taskCache.getOutboxBatch).toHaveBeenCalledTimes(1);
		expect(tasksAPI.sync).toHaveBeenCalledTimes(1);
	});

	it('returns null from flush on sync errors', async () => {
		const { flushTaskOutbox } = await loadTaskSyncService();
		taskCache.getOutboxBatch.mockResolvedValue([]);
		tasksAPI.sync.mockRejectedValue(new Error('sync failed'));

		await expect(flushTaskOutbox()).resolves.toBeNull();
	});

	it('syncTaskUpdates returns null when offline', async () => {
		setOnline(false);
		const { syncTaskUpdates } = await loadTaskSyncService();

		await expect(syncTaskUpdates()).resolves.toBeNull();
		expect(tasksAPI.sync).not.toHaveBeenCalled();
	});

	it('syncTaskUpdates applies updates and handles failures', async () => {
		const { syncTaskUpdates } = await loadTaskSyncService();
		taskCache.getLastSync.mockResolvedValue('2026-02-17T09:00:00Z');

		const success = await syncTaskUpdates();
		expect(success).toEqual(createSyncResponse());
		expect(tasksAPI.sync).toHaveBeenCalledWith({
			last_sync: '2026-02-17T09:00:00Z',
			operations: []
		});
		expect(taskCache.applySyncUpdates).toHaveBeenCalledWith({
			tasks: [],
			projects: [],
			groups: []
		});
		expect(taskCache.setLastSync).toHaveBeenCalledWith('2026-02-17T10:00:00Z');

		tasksAPI.sync.mockRejectedValueOnce(new Error('network error'));
		await expect(syncTaskUpdates()).resolves.toBeNull();
	});
});
