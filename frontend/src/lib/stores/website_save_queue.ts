export interface QueuedWebsiteSave {
	operationId: string;
	url: string;
	queuedAt: string;
}

const STORAGE_KEY = 'sideBar.websiteSaveQueue';
let memoryQueue: QueuedWebsiteSave[] = [];

const canUseStorage = () => {
	try {
		return typeof localStorage !== 'undefined';
	} catch {
		return false;
	}
};

const buildOperationId = () => {
	if (globalThis.crypto?.randomUUID) {
		return globalThis.crypto.randomUUID();
	}
	return `website-save-${Date.now()}-${Math.random().toString(16).slice(2)}`;
};

const normalizeQueue = (value: unknown): QueuedWebsiteSave[] => {
	if (!Array.isArray(value)) return [];
	return value
		.filter(
			(item): item is QueuedWebsiteSave =>
				!!item &&
				typeof item === 'object' &&
				typeof (item as QueuedWebsiteSave).operationId === 'string' &&
				typeof (item as QueuedWebsiteSave).url === 'string' &&
				typeof (item as QueuedWebsiteSave).queuedAt === 'string'
		)
		.sort((left, right) => left.queuedAt.localeCompare(right.queuedAt));
};

const readQueue = (): QueuedWebsiteSave[] => {
	if (!canUseStorage()) {
		return [...memoryQueue];
	}
	try {
		return normalizeQueue(JSON.parse(localStorage.getItem(STORAGE_KEY) ?? '[]'));
	} catch {
		return [];
	}
};

const writeQueue = (queue: QueuedWebsiteSave[]): void => {
	memoryQueue = [...queue];
	if (!canUseStorage()) {
		return;
	}
	localStorage.setItem(STORAGE_KEY, JSON.stringify(queue));
};

/**
 * Persist queued website-save requests across auth loss and refreshes.
 */
export const websiteSaveQueue = {
	/**
	 * Add a website URL to the queue, deduplicating by normalized URL.
	 */
	async enqueueSave(url: string): Promise<QueuedWebsiteSave> {
		const queue = readQueue();
		const existing = queue.find((entry) => entry.url === url);
		if (existing) {
			return existing;
		}

		const entry: QueuedWebsiteSave = {
			operationId: buildOperationId(),
			url,
			queuedAt: new Date().toISOString()
		};
		writeQueue([...queue, entry]);
		return entry;
	},

	/**
	 * List queued website saves in enqueue order.
	 */
	async listQueuedSaves(): Promise<QueuedWebsiteSave[]> {
		return readQueue();
	},

	/**
	 * Remove queued website saves after they have been replayed successfully.
	 */
	async removeQueuedSaves(operationIds: string[]): Promise<void> {
		if (!operationIds.length) return;
		writeQueue(readQueue().filter((entry) => !operationIds.includes(entry.operationId)));
	}
};
