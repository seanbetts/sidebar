import { tasksAPI } from '$lib/services/api';
import {
	applySyncUpdates,
	enqueueOperation,
	getLastSync,
	getOutboxBatch,
	loadTaskCacheSnapshot,
	removeOutboxOperations,
	setLastSync,
	upsertGroups,
	upsertProjects,
	upsertTasks
} from '$lib/stores/task_cache';
import type {
	TaskListResponse,
	TaskSyncOperation,
	TaskSyncResponse,
	TaskSyncUpdates
} from '$lib/types/tasks';

const OUTBOX_BATCH_SIZE = 50;
let flushPromise: Promise<TaskSyncResponse | null> | null = null;

const isOnline = () => typeof navigator !== 'undefined' && navigator.onLine;

const buildOperationId = () => {
	if (globalThis.crypto?.randomUUID) {
		return globalThis.crypto.randomUUID();
	}
	return `op-${Date.now()}-${Math.random().toString(16).slice(2)}`;
};

const withOperationMetadata = (operation: Partial<TaskSyncOperation>): TaskSyncOperation => ({
	...operation,
	operation_id: operation.operation_id ?? buildOperationId(),
	client_updated_at: operation.client_updated_at ?? new Date().toISOString()
});

const applyResponseTasks = async (response: TaskSyncResponse) => {
	const updates: TaskSyncUpdates = response.updates ?? { tasks: [], projects: [], groups: [] };
	await applySyncUpdates(updates);
	await upsertTasks([...(response.tasks ?? []), ...(response.nextTasks ?? [])]);
};

/**
 * Hydrate tasks cache data for initial render.
 */
export async function hydrateTaskCache() {
	return loadTaskCacheSnapshot();
}

/**
 * Cache a task list response for offline use.
 */
export async function cacheTaskListResponse(response: TaskListResponse): Promise<void> {
	await Promise.all([
		upsertTasks(response.tasks ?? []),
		upsertProjects(response.projects ?? []),
		upsertGroups(response.groups ?? [])
	]);
}

/**
 * Enqueue an operation and flush immediately if online.
 */
export async function enqueueTaskOperation(
	operation: Partial<TaskSyncOperation>
): Promise<TaskSyncResponse | null> {
	const normalized = withOperationMetadata(operation);
	await enqueueOperation(normalized);
	if (!isOnline()) {
		return null;
	}
	return flushTaskOutbox();
}

/**
 * Flush queued operations to the sync endpoint.
 */
export async function flushTaskOutbox(): Promise<TaskSyncResponse | null> {
	if (flushPromise) {
		return flushPromise;
	}
	flushPromise = (async () => {
		if (!isOnline()) {
			return null;
		}
		const [lastSync, batch] = await Promise.all([getLastSync(), getOutboxBatch(OUTBOX_BATCH_SIZE)]);
		if (!batch.length) {
			const response = await tasksAPI.sync({ last_sync: lastSync, operations: [] });
			await applyResponseTasks(response);
			await setLastSync(response.serverUpdatedSince);
			return response;
		}
		const response = await tasksAPI.sync({ last_sync: lastSync, operations: batch });
		await Promise.all([
			removeOutboxOperations(response.applied ?? []),
			applyResponseTasks(response),
			setLastSync(response.serverUpdatedSince)
		]);
		return response;
	})()
		.catch(() => null)
		.finally(() => {
			flushPromise = null;
		});
	return flushPromise;
}

/**
 * Pull server updates without sending new operations.
 */
export async function syncTaskUpdates(): Promise<TaskSyncResponse | null> {
	if (!isOnline()) {
		return null;
	}
	const lastSync = await getLastSync();
	try {
		const response = await tasksAPI.sync({ last_sync: lastSync, operations: [] });
		await applyResponseTasks(response);
		await setLastSync(response.serverUpdatedSince);
		return response;
	} catch {
		return null;
	}
}
