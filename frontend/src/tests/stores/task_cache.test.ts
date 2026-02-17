import type { Task, TaskGroup, TaskProject, TaskSyncUpdates } from '$lib/types/tasks';
import { IDBFactory } from 'fake-indexeddb';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

type TaskCacheModule = typeof import('$lib/stores/task_cache');

const DB_NAME = 'sidebar-tasks';

const createTask = (id: string, title = `Task ${id}`): Task => ({
	id,
	title,
	status: 'open',
	deadline: null,
	notes: null,
	projectId: null,
	groupId: null,
	repeating: false,
	repeatTemplate: false,
	updatedAt: null,
	deletedAt: null
});

const createProject = (id: string, title = `Project ${id}`): TaskProject => ({
	id,
	title,
	groupId: null,
	status: 'active'
});

const createGroup = (id: string, title = `Group ${id}`): TaskGroup => ({
	id,
	title
});

const importTaskCache = async (): Promise<TaskCacheModule> => import('$lib/stores/task_cache');

const seedLegacyAreasStore = async (factory: IDBFactory, groups: TaskGroup[]): Promise<void> =>
	new Promise((resolve, reject) => {
		const request = factory.open(DB_NAME, 1);
		request.onupgradeneeded = () => {
			const db = request.result;
			if (!db.objectStoreNames.contains('tasks')) {
				db.createObjectStore('tasks', { keyPath: 'id' });
			}
			if (!db.objectStoreNames.contains('projects')) {
				db.createObjectStore('projects', { keyPath: 'id' });
			}
			const areasStore = db.createObjectStore('areas', { keyPath: 'id' });
			groups.forEach((group) => {
				areasStore.put(group);
			});
		};
		request.onsuccess = () => {
			request.result.close();
			resolve();
		};
		request.onerror = () => reject(request.error ?? new Error('Failed to seed legacy store'));
	});

describe('task_cache (memory fallback)', () => {
	let taskCache: TaskCacheModule;

	beforeEach(async () => {
		vi.resetModules();
		vi.stubGlobal('indexedDB', undefined);
		taskCache = await importTaskCache();
	});

	afterEach(() => {
		vi.unstubAllGlobals();
	});

	it('returns empty snapshot initially', async () => {
		const snapshot = await taskCache.loadTaskCacheSnapshot();

		expect(snapshot).toEqual({
			tasks: [],
			projects: [],
			groups: [],
			lastSync: null
		});
	});

	it('upserts tasks, projects, and groups in memory', async () => {
		await taskCache.upsertTasks([createTask('task-1')]);
		await taskCache.upsertProjects([createProject('project-1')]);
		await taskCache.upsertGroups([createGroup('group-1')]);

		const snapshot = await taskCache.loadTaskCacheSnapshot();
		expect(snapshot.tasks.map((task) => task.id)).toEqual(['task-1']);
		expect(snapshot.projects.map((project) => project.id)).toEqual(['project-1']);
		expect(snapshot.groups.map((group) => group.id)).toEqual(['group-1']);
	});

	it('applies sync updates and handles undefined arrays', async () => {
		await taskCache.applySyncUpdates({} as unknown as TaskSyncUpdates);
		await taskCache.applySyncUpdates({
			tasks: [createTask('task-1')],
			projects: [createProject('project-1')],
			groups: [createGroup('group-1')]
		});

		const snapshot = await taskCache.loadTaskCacheSnapshot();
		expect(snapshot.tasks).toHaveLength(1);
		expect(snapshot.projects).toHaveLength(1);
		expect(snapshot.groups).toHaveLength(1);
	});

	it('tracks last sync in memory', async () => {
		const timestamp = '2026-02-17T12:00:00Z';

		await taskCache.setLastSync(timestamp);
		expect(await taskCache.getLastSync()).toBe(timestamp);

		await taskCache.setLastSync(null);
		expect(await taskCache.getLastSync()).toBe(null);
	});

	it('enqueues, lists, and removes outbox operations in memory', async () => {
		await taskCache.enqueueOperation({ operation_id: 'op-1', op: 'create', id: 'task-1' });
		await taskCache.enqueueOperation({ operation_id: 'op-2', op: 'update', id: 'task-2' });

		const limitedBatch = await taskCache.getOutboxBatch(1);
		expect(limitedBatch).toHaveLength(1);
		expect(limitedBatch[0].operation_id).toBe('op-1');
		expect(limitedBatch[0]).not.toHaveProperty('queued_at');

		await taskCache.removeOutboxOperations(['missing-op']);
		await taskCache.removeOutboxOperations([]);
		await taskCache.removeOutboxOperations(['op-1']);

		const remaining = await taskCache.getOutboxBatch(10);
		expect(remaining.map((entry) => entry.operation_id)).toEqual(['op-2']);
	});
});

describe('task_cache (indexeddb)', () => {
	let taskCache: TaskCacheModule;
	let indexedDbFactory: IDBFactory;

	beforeEach(() => {
		vi.resetModules();
		indexedDbFactory = new IDBFactory();
		vi.stubGlobal('indexedDB', indexedDbFactory);
	});

	afterEach(() => {
		vi.useRealTimers();
		vi.unstubAllGlobals();
	});

	it('persists snapshot data in indexeddb', async () => {
		taskCache = await importTaskCache();
		const syncTimestamp = '2026-02-17T12:34:56Z';

		await taskCache.upsertTasks([createTask('task-1')]);
		await taskCache.upsertProjects([createProject('project-1')]);
		await taskCache.upsertGroups([createGroup('group-1')]);
		await taskCache.setLastSync(syncTimestamp);

		const snapshot = await taskCache.loadTaskCacheSnapshot();
		expect(snapshot.tasks.map((task) => task.id)).toEqual(['task-1']);
		expect(snapshot.projects.map((project) => project.id)).toEqual(['project-1']);
		expect(snapshot.groups.map((group) => group.id)).toEqual(['group-1']);
		expect(snapshot.lastSync).toBe(syncTimestamp);
	});

	it('applies sync updates in indexeddb and clears sync timestamp', async () => {
		taskCache = await importTaskCache();
		await taskCache.applySyncUpdates({
			tasks: [createTask('task-1')],
			projects: [createProject('project-1')],
			groups: [createGroup('group-1')]
		});
		await taskCache.setLastSync('2026-02-17T12:00:00Z');
		await taskCache.setLastSync(null);

		const snapshot = await taskCache.loadTaskCacheSnapshot();
		expect(snapshot.tasks).toHaveLength(1);
		expect(snapshot.projects).toHaveLength(1);
		expect(snapshot.groups).toHaveLength(1);
		expect(snapshot.lastSync).toBe(null);
		expect(await taskCache.getLastSync()).toBe(null);
	});

	it('sorts and truncates outbox batch in indexeddb', async () => {
		taskCache = await importTaskCache();
		await taskCache.loadTaskCacheSnapshot();
		await new Promise<void>((resolve, reject) => {
			const request = indexedDbFactory.open(DB_NAME, 2);
			request.onsuccess = () => {
				const db = request.result;
				const transaction = db.transaction('operations', 'readwrite');
				const store = transaction.objectStore('operations');
				store.put({
					operation_id: 'op-2',
					op: 'create',
					id: 'task-2',
					queued_at: '2026-02-17T10:00:00.000Z'
				});
				store.put({
					operation_id: 'op-1',
					op: 'create',
					id: 'task-1',
					queued_at: '2026-02-17T09:59:00.000Z'
				});
				transaction.oncomplete = () => {
					db.close();
					resolve();
				};
				transaction.onerror = () =>
					reject(transaction.error ?? new Error('Failed to seed operations'));
				transaction.onabort = () =>
					reject(transaction.error ?? new Error('Aborted while seeding operations'));
			};
			request.onerror = () => reject(request.error ?? new Error('Failed to open database'));
		});

		const batch = await taskCache.getOutboxBatch(1);
		expect(batch).toHaveLength(1);
		expect(batch[0].operation_id).toBe('op-1');
		expect(batch[0]).not.toHaveProperty('queued_at');
	});

	it('removes indexeddb outbox operations by id', async () => {
		taskCache = await importTaskCache();
		await taskCache.enqueueOperation({ operation_id: 'op-1', op: 'create', id: 'task-1' });
		await taskCache.enqueueOperation({ operation_id: 'op-2', op: 'create', id: 'task-2' });

		await taskCache.removeOutboxOperations(['op-1']);
		const remaining = await taskCache.getOutboxBatch(10);
		expect(remaining.map((entry) => entry.operation_id)).toEqual(['op-2']);
	});

	it('migrates legacy areas store into groups on database upgrade', async () => {
		await seedLegacyAreasStore(indexedDbFactory, [createGroup('legacy-group', 'Legacy Group')]);

		taskCache = await importTaskCache();
		const snapshot = await taskCache.loadTaskCacheSnapshot();

		expect(snapshot.groups).toEqual([createGroup('legacy-group', 'Legacy Group')]);
	});
});
