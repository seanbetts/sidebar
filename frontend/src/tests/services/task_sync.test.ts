import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enqueueTaskOperation, flushTaskOutbox } from '$lib/services/task_sync';

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

const setOnline = (isOnline: boolean) => {
	Object.defineProperty(globalThis, 'navigator', {
		value: { onLine: isOnline },
		configurable: true
	});
};

describe('task_sync service', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		setOnline(true);
	});

	afterEach(() => {
		Object.defineProperty(globalThis, 'navigator', {
			value: originalNavigator,
			configurable: true
		});
	});

	it('enqueues operations and skips flush when offline', async () => {
		setOnline(false);
		taskCache.enqueueOperation.mockResolvedValue({
			op: 'add',
			operation_id: 'op-1',
			client_updated_at: '2025-01-01T00:00:00Z'
		});

		const response = await enqueueTaskOperation({ op: 'add', title: 'Offline task' });

		expect(response).toBeNull();
		expect(tasksAPI.sync).not.toHaveBeenCalled();
		expect(taskCache.enqueueOperation).toHaveBeenCalledTimes(1);
		const [payload] = taskCache.enqueueOperation.mock.calls[0];
		expect(payload.operation_id).toBeTruthy();
		expect(payload.client_updated_at).toBeTruthy();
	});

	it('flushes queued operations and applies updates', async () => {
		taskCache.getLastSync.mockResolvedValue('2025-01-01T00:00:00Z');
		taskCache.getOutboxBatch.mockResolvedValue([
			{
				op: 'rename',
				id: 'task-1',
				operation_id: 'op-1',
				client_updated_at: '2025-01-01T00:00:00Z',
				title: 'Updated'
			}
		]);
		tasksAPI.sync.mockResolvedValue({
			applied: ['op-1'],
			serverUpdatedSince: '2025-01-01T01:00:00Z',
			updates: { tasks: [], projects: [], groups: [] },
			tasks: [
				{
					id: 'task-1',
					title: 'Updated',
					status: 'open',
					groupId: null,
					projectId: null
				}
			],
			nextTasks: []
		});

		await flushTaskOutbox();

		expect(tasksAPI.sync).toHaveBeenCalledWith({
			last_sync: '2025-01-01T00:00:00Z',
			operations: [
				{
					op: 'rename',
					id: 'task-1',
					operation_id: 'op-1',
					client_updated_at: '2025-01-01T00:00:00Z',
					title: 'Updated'
				}
			]
		});
		expect(taskCache.removeOutboxOperations).toHaveBeenCalledWith(['op-1']);
		expect(taskCache.applySyncUpdates).toHaveBeenCalledWith({
			tasks: [],
			projects: [],
			groups: []
		});
		expect(taskCache.upsertTasks).toHaveBeenCalledWith([
			{
				id: 'task-1',
				title: 'Updated',
				status: 'open',
				groupId: null,
				projectId: null
			}
		]);
		expect(taskCache.setLastSync).toHaveBeenCalledWith('2025-01-01T01:00:00Z');
	});

	it('flushes with empty batch and skips outbox removal', async () => {
		taskCache.getLastSync.mockResolvedValue(null);
		taskCache.getOutboxBatch.mockResolvedValue([]);
		tasksAPI.sync.mockResolvedValue({
			serverUpdatedSince: '2025-01-01T01:00:00Z',
			updates: { tasks: [], projects: [], groups: [] },
			tasks: [],
			nextTasks: []
		});

		await flushTaskOutbox();

		expect(tasksAPI.sync).toHaveBeenCalledWith({ last_sync: null, operations: [] });
		expect(taskCache.removeOutboxOperations).not.toHaveBeenCalled();
		expect(taskCache.setLastSync).toHaveBeenCalledWith('2025-01-01T01:00:00Z');
	});
});
