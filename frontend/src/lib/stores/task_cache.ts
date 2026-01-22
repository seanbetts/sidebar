import type {
	Task,
	TaskArea,
	TaskProject,
	TaskSyncOperation,
	TaskSyncUpdates
} from '$lib/types/tasks';

export type TaskCacheSnapshot = {
	tasks: Task[];
	projects: TaskProject[];
	areas: TaskArea[];
	lastSync: string | null;
};

type TaskOutboxEntry = TaskSyncOperation & { queued_at: string };

const DB_NAME = 'sidebar-tasks';
const DB_VERSION = 1;
const STORE_TASKS = 'tasks';
const STORE_PROJECTS = 'projects';
const STORE_AREAS = 'areas';
const STORE_OPERATIONS = 'operations';
const STORE_SYNC_STATE = 'sync_state';
const SYNC_KEY = 'tasks.last_sync';

const memoryState = {
	tasks: new Map<string, Task>(),
	projects: new Map<string, TaskProject>(),
	areas: new Map<string, TaskArea>(),
	operations: [] as TaskOutboxEntry[],
	lastSync: null as string | null
};

let dbPromise: Promise<IDBDatabase | null> | null = null;

const isIndexedDbAvailable = () => typeof indexedDB !== 'undefined';

const requestToPromise = <T>(request: IDBRequest<T>): Promise<T> =>
	new Promise((resolve, reject) => {
		request.onsuccess = () => resolve(request.result);
		request.onerror = () => reject(request.error);
	});

const openDb = (): Promise<IDBDatabase | null> => {
	if (!isIndexedDbAvailable()) {
		return Promise.resolve(null);
	}
	if (!dbPromise) {
		dbPromise = new Promise((resolve, reject) => {
			const request = indexedDB.open(DB_NAME, DB_VERSION);
			request.onupgradeneeded = () => {
				const db = request.result;
				if (!db.objectStoreNames.contains(STORE_TASKS)) {
					db.createObjectStore(STORE_TASKS, { keyPath: 'id' });
				}
				if (!db.objectStoreNames.contains(STORE_PROJECTS)) {
					db.createObjectStore(STORE_PROJECTS, { keyPath: 'id' });
				}
				if (!db.objectStoreNames.contains(STORE_AREAS)) {
					db.createObjectStore(STORE_AREAS, { keyPath: 'id' });
				}
				if (!db.objectStoreNames.contains(STORE_OPERATIONS)) {
					const store = db.createObjectStore(STORE_OPERATIONS, {
						keyPath: 'operation_id'
					});
					store.createIndex('queued_at', 'queued_at');
				}
				if (!db.objectStoreNames.contains(STORE_SYNC_STATE)) {
					db.createObjectStore(STORE_SYNC_STATE, { keyPath: 'key' });
				}
			};
			request.onsuccess = () => resolve(request.result);
			request.onerror = () => reject(request.error);
		});
	}
	return dbPromise;
};

const runTransaction = async <T>(
	storeNames: string[],
	mode: IDBTransactionMode,
	operation: (stores: Record<string, IDBObjectStore>) => Promise<T>
): Promise<T> => {
	const db = await openDb();
	if (!db) {
		throw new Error('IndexedDB unavailable');
	}
	return new Promise((resolve, reject) => {
		const tx = db.transaction(storeNames, mode);
		const stores: Record<string, IDBObjectStore> = {};
		storeNames.forEach((name) => {
			stores[name] = tx.objectStore(name);
		});
		operation(stores)
			.then((result) => {
				tx.oncomplete = () => resolve(result);
				tx.onerror = () => reject(tx.error);
				tx.onabort = () => reject(tx.error);
			})
			.catch(reject);
	});
};

/**
 * Load cached tasks, projects, areas, and sync state.
 */
export async function loadTaskCacheSnapshot(): Promise<TaskCacheSnapshot> {
	if (!isIndexedDbAvailable()) {
		return {
			tasks: Array.from(memoryState.tasks.values()),
			projects: Array.from(memoryState.projects.values()),
			areas: Array.from(memoryState.areas.values()),
			lastSync: memoryState.lastSync
		};
	}
	return runTransaction(
		[STORE_TASKS, STORE_PROJECTS, STORE_AREAS, STORE_SYNC_STATE],
		'readonly',
		async (stores) => {
			const [tasks, projects, areas, syncState] = await Promise.all([
				requestToPromise<Task[]>(stores[STORE_TASKS].getAll()),
				requestToPromise<TaskProject[]>(stores[STORE_PROJECTS].getAll()),
				requestToPromise<TaskArea[]>(stores[STORE_AREAS].getAll()),
				requestToPromise<{ key: string; value: string } | undefined>(
					stores[STORE_SYNC_STATE].get(SYNC_KEY)
				)
			]);
			return {
				tasks,
				projects,
				areas,
				lastSync: syncState?.value ?? null
			};
		}
	);
}

/**
 * Persist tasks in the cache store.
 */
export async function upsertTasks(tasks: Task[]): Promise<void> {
	if (!tasks.length) return;
	if (!isIndexedDbAvailable()) {
		tasks.forEach((task) => memoryState.tasks.set(task.id, task));
		return;
	}
	await runTransaction([STORE_TASKS], 'readwrite', async (stores) => {
		tasks.forEach((task) => {
			stores[STORE_TASKS].put(task);
		});
	});
}

/**
 * Persist projects in the cache store.
 */
export async function upsertProjects(projects: TaskProject[]): Promise<void> {
	if (!projects.length) return;
	if (!isIndexedDbAvailable()) {
		projects.forEach((project) => memoryState.projects.set(project.id, project));
		return;
	}
	await runTransaction([STORE_PROJECTS], 'readwrite', async (stores) => {
		projects.forEach((project) => {
			stores[STORE_PROJECTS].put(project);
		});
	});
}

/**
 * Persist areas in the cache store.
 */
export async function upsertAreas(areas: TaskArea[]): Promise<void> {
	if (!areas.length) return;
	if (!isIndexedDbAvailable()) {
		areas.forEach((area) => memoryState.areas.set(area.id, area));
		return;
	}
	await runTransaction([STORE_AREAS], 'readwrite', async (stores) => {
		areas.forEach((area) => {
			stores[STORE_AREAS].put(area);
		});
	});
}

/**
 * Apply sync updates to the cache store.
 */
export async function applySyncUpdates(updates: TaskSyncUpdates): Promise<void> {
	await Promise.all([
		upsertTasks(updates.tasks ?? []),
		upsertProjects(updates.projects ?? []),
		upsertAreas(updates.areas ?? [])
	]);
}

/**
 * Persist the last successful sync timestamp.
 */
export async function setLastSync(value: string | null): Promise<void> {
	if (!isIndexedDbAvailable()) {
		memoryState.lastSync = value;
		return;
	}
	await runTransaction([STORE_SYNC_STATE], 'readwrite', async (stores) => {
		if (!value) {
			stores[STORE_SYNC_STATE].delete(SYNC_KEY);
		} else {
			stores[STORE_SYNC_STATE].put({ key: SYNC_KEY, value });
		}
	});
}

/**
 * Load the last successful sync timestamp.
 */
export async function getLastSync(): Promise<string | null> {
	if (!isIndexedDbAvailable()) {
		return memoryState.lastSync;
	}
	return runTransaction([STORE_SYNC_STATE], 'readonly', async (stores) => {
		const state = await requestToPromise<{ key: string; value: string } | undefined>(
			stores[STORE_SYNC_STATE].get(SYNC_KEY)
		);
		return state?.value ?? null;
	});
}

/**
 * Enqueue an outbox operation for offline replay.
 */
export async function enqueueOperation(operation: TaskSyncOperation): Promise<TaskOutboxEntry> {
	const entry: TaskOutboxEntry = {
		...operation,
		queued_at: new Date().toISOString()
	};
	if (!isIndexedDbAvailable()) {
		memoryState.operations.push(entry);
		return entry;
	}
	await runTransaction([STORE_OPERATIONS], 'readwrite', async (stores) => {
		stores[STORE_OPERATIONS].put(entry);
	});
	return entry;
}

/**
 * Read a batch of outbox operations, sorted by queued time.
 */
export async function getOutboxBatch(limit: number): Promise<TaskSyncOperation[]> {
	if (!isIndexedDbAvailable()) {
		return memoryState.operations
			.slice()
			.sort((a, b) => a.queued_at.localeCompare(b.queued_at))
			.slice(0, limit)
			.map(({ queued_at, ...rest }) => rest);
	}
	return runTransaction([STORE_OPERATIONS], 'readonly', async (stores) => {
		const entries = await requestToPromise<TaskOutboxEntry[]>(stores[STORE_OPERATIONS].getAll());
		return entries
			.sort((a, b) => a.queued_at.localeCompare(b.queued_at))
			.slice(0, limit)
			.map(({ queued_at, ...rest }) => rest);
	});
}

/**
 * Remove applied outbox operations.
 */
export async function removeOutboxOperations(operationIds: string[]): Promise<void> {
	if (!operationIds.length) return;
	if (!isIndexedDbAvailable()) {
		memoryState.operations = memoryState.operations.filter(
			(entry) => !operationIds.includes(entry.operation_id)
		);
		return;
	}
	await runTransaction([STORE_OPERATIONS], 'readwrite', async (stores) => {
		operationIds.forEach((operationId) => {
			stores[STORE_OPERATIONS].delete(operationId);
		});
	});
}
