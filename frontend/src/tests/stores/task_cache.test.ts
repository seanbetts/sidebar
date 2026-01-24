import { describe, expect, it, vi, beforeEach, beforeAll } from 'vitest';

// Mock IndexedDB as unavailable to use memory fallback
vi.stubGlobal('indexedDB', undefined);

type TaskCacheModule = typeof import('$lib/stores/task_cache');

describe('task_cache (memory fallback)', () => {
	let taskCache: TaskCacheModule;

	beforeAll(async () => {
		// Initial import to warm up
		taskCache = await import('$lib/stores/task_cache');
	});

	beforeEach(async () => {
		// Reset modules and get fresh import for each test
		vi.resetModules();
		taskCache = await import('$lib/stores/task_cache');
	});

	describe('loadTaskCacheSnapshot', () => {
		it('returns empty snapshot initially', async () => {
			const snapshot = await taskCache.loadTaskCacheSnapshot();

			expect(snapshot).toEqual({
				tasks: [],
				projects: [],
				groups: [],
				lastSync: null
			});
		});
	});

	describe('upsertTasks', () => {
		it('stores tasks in memory', async () => {
			const tasks = [
				{
					id: 'task-1',
					title: 'Task 1',
					status: 'open' as const,
					deadline: null,
					notes: null,
					projectId: null,
					groupId: null,
					repeating: false,
					repeatTemplate: false,
					updatedAt: null,
					deletedAt: null
				}
			];

			await taskCache.upsertTasks(tasks);
			const snapshot = await taskCache.loadTaskCacheSnapshot();

			expect(snapshot.tasks).toHaveLength(1);
			expect(snapshot.tasks[0].id).toBe('task-1');
		});

		it('does nothing with empty array', async () => {
			await taskCache.upsertTasks([]);
			const snapshot = await taskCache.loadTaskCacheSnapshot();

			expect(snapshot.tasks).toHaveLength(0);
		});

		it('overwrites existing tasks with same id', async () => {
			const task1 = {
				id: 'task-1',
				title: 'Original',
				status: 'open' as const,
				deadline: null,
				notes: null,
				projectId: null,
				groupId: null,
				repeating: false,
				repeatTemplate: false,
				updatedAt: null,
				deletedAt: null
			};

			const task2 = { ...task1, title: 'Updated' };

			await taskCache.upsertTasks([task1]);
			await taskCache.upsertTasks([task2]);
			const snapshot = await taskCache.loadTaskCacheSnapshot();

			expect(snapshot.tasks).toHaveLength(1);
			expect(snapshot.tasks[0].title).toBe('Updated');
		});
	});

	describe('upsertProjects', () => {
		it('stores projects in memory', async () => {
			const projects = [{ id: 'proj-1', title: 'Project 1', groupId: null }];

			await taskCache.upsertProjects(projects);
			const snapshot = await taskCache.loadTaskCacheSnapshot();

			expect(snapshot.projects).toHaveLength(1);
			expect(snapshot.projects[0].id).toBe('proj-1');
		});

		it('does nothing with empty array', async () => {
			await taskCache.upsertProjects([]);
			const snapshot = await taskCache.loadTaskCacheSnapshot();

			expect(snapshot.projects).toHaveLength(0);
		});
	});

	describe('upsertGroups', () => {
		it('stores groups in memory', async () => {
			const groups = [{ id: 'group-1', title: 'Group 1' }];

			await taskCache.upsertGroups(groups);
			const snapshot = await taskCache.loadTaskCacheSnapshot();

			expect(snapshot.groups).toHaveLength(1);
			expect(snapshot.groups[0].id).toBe('group-1');
		});

		it('does nothing with empty array', async () => {
			await taskCache.upsertGroups([]);
			const snapshot = await taskCache.loadTaskCacheSnapshot();

			expect(snapshot.groups).toHaveLength(0);
		});
	});

	describe('applySyncUpdates', () => {
		it('applies tasks, projects, and groups in batch', async () => {
			await taskCache.applySyncUpdates({
				tasks: [
					{
						id: 'task-1',
						title: 'Task',
						status: 'open',
						deadline: null,
						notes: null,
						projectId: null,
						groupId: null,
						repeating: false,
						repeatTemplate: false,
						updatedAt: null,
						deletedAt: null
					}
				],
				projects: [{ id: 'proj-1', title: 'Project', groupId: null }],
				groups: [{ id: 'group-1', title: 'Group' }]
			});

			const snapshot = await taskCache.loadTaskCacheSnapshot();

			expect(snapshot.tasks).toHaveLength(1);
			expect(snapshot.projects).toHaveLength(1);
			expect(snapshot.groups).toHaveLength(1);
		});

		it('handles undefined arrays', async () => {
			await taskCache.applySyncUpdates({});
			const snapshot = await taskCache.loadTaskCacheSnapshot();

			expect(snapshot.tasks).toHaveLength(0);
			expect(snapshot.projects).toHaveLength(0);
			expect(snapshot.groups).toHaveLength(0);
		});
	});

	describe('setLastSync / getLastSync', () => {
		it('stores and retrieves last sync timestamp', async () => {
			const timestamp = '2026-01-23T12:00:00Z';

			await taskCache.setLastSync(timestamp);
			const result = await taskCache.getLastSync();

			expect(result).toBe(timestamp);
		});

		it('clears last sync with null', async () => {
			await taskCache.setLastSync('2026-01-23T12:00:00Z');
			await taskCache.setLastSync(null);
			const result = await taskCache.getLastSync();

			expect(result).toBe(null);
		});

		it('returns null when not set', async () => {
			const result = await taskCache.getLastSync();
			expect(result).toBe(null);
		});
	});

	describe('enqueueOperation', () => {
		it('adds operation with timestamp', async () => {
			const operation = {
				operation_id: 'op-1',
				op: 'create' as const,
				id: 'task-1',
				title: 'New Task'
			};

			const entry = await taskCache.enqueueOperation(operation);

			expect(entry.operation_id).toBe('op-1');
			expect(entry.queued_at).toBeDefined();
			expect(new Date(entry.queued_at).getTime()).toBeLessThanOrEqual(Date.now());
		});
	});

	describe('getOutboxBatch', () => {
		it('returns operations sorted by queued time', async () => {
			await taskCache.enqueueOperation({
				operation_id: 'op-1',
				op: 'create' as const,
				id: 'task-1'
			});
			await taskCache.enqueueOperation({
				operation_id: 'op-2',
				op: 'create' as const,
				id: 'task-2'
			});

			const batch = await taskCache.getOutboxBatch(10);

			expect(batch).toHaveLength(2);
			expect(batch[0].operation_id).toBe('op-1');
			expect(batch[1].operation_id).toBe('op-2');
		});

		it('respects limit', async () => {
			await taskCache.enqueueOperation({
				operation_id: 'op-1',
				op: 'create' as const,
				id: 'task-1'
			});
			await taskCache.enqueueOperation({
				operation_id: 'op-2',
				op: 'create' as const,
				id: 'task-2'
			});

			const batch = await taskCache.getOutboxBatch(1);

			expect(batch).toHaveLength(1);
		});

		it('excludes queued_at from returned operations', async () => {
			await taskCache.enqueueOperation({
				operation_id: 'op-1',
				op: 'create' as const,
				id: 'task-1'
			});

			const batch = await taskCache.getOutboxBatch(10);

			expect(batch[0]).not.toHaveProperty('queued_at');
		});
	});

	describe('removeOutboxOperations', () => {
		it('removes specified operations', async () => {
			await taskCache.enqueueOperation({
				operation_id: 'op-1',
				op: 'create' as const,
				id: 'task-1'
			});
			await taskCache.enqueueOperation({
				operation_id: 'op-2',
				op: 'create' as const,
				id: 'task-2'
			});

			await taskCache.removeOutboxOperations(['op-1']);
			const batch = await taskCache.getOutboxBatch(10);

			expect(batch).toHaveLength(1);
			expect(batch[0].operation_id).toBe('op-2');
		});

		it('does nothing with empty array', async () => {
			await taskCache.enqueueOperation({
				operation_id: 'op-1',
				op: 'create' as const,
				id: 'task-1'
			});

			await taskCache.removeOutboxOperations([]);
			const batch = await taskCache.getOutboxBatch(10);

			expect(batch).toHaveLength(1);
		});

		it('handles non-existent operation ids', async () => {
			await taskCache.enqueueOperation({
				operation_id: 'op-1',
				op: 'create' as const,
				id: 'task-1'
			});

			await taskCache.removeOutboxOperations(['op-999']);
			const batch = await taskCache.getOutboxBatch(10);

			expect(batch).toHaveLength(1);
		});
	});
});
