import { websitesAPI } from '$lib/services/api';
import { websiteSaveQueue, type QueuedWebsiteSave } from '$lib/stores/website_save_queue';
import { logError } from '$lib/utils/errorHandling';

type WebsiteSavePayload = Awaited<ReturnType<typeof websitesAPI.save>>;
type SavedWebsiteDetail = NonNullable<WebsiteSavePayload['website']>;

let flushPromise: Promise<SavedWebsiteDetail[]> | null = null;

const isOnline = () => typeof navigator !== 'undefined' && navigator.onLine;

const getStatus = (error: unknown): number | null => {
	if (!error || typeof error !== 'object') return null;
	const status = (error as { status?: unknown }).status;
	return typeof status === 'number' ? status : null;
};

const extractSavedWebsite = (payload: WebsiteSavePayload): SavedWebsiteDetail | null => {
	return payload.success && payload.website ? payload.website : null;
};

/**
 * Queue a website URL for replay after auth is restored.
 */
export async function enqueueWebsiteSave(url: string): Promise<QueuedWebsiteSave> {
	return websiteSaveQueue.enqueueSave(url);
}

/**
 * Replay queued website saves through the normal save endpoint.
 */
export async function flushQueuedWebsiteSaves(): Promise<SavedWebsiteDetail[]> {
	if (!isOnline()) {
		return [];
	}
	if (flushPromise) {
		return flushPromise;
	}

	flushPromise = (async () => {
		const queue = await websiteSaveQueue.listQueuedSaves();
		if (!queue.length) {
			return [];
		}

		const saved: SavedWebsiteDetail[] = [];
		const completedIds: string[] = [];

		for (const entry of queue) {
			try {
				const payload = await websitesAPI.save(entry.url);
				const website = extractSavedWebsite(payload);
				if (!website) {
					throw new Error('Failed to save queued website');
				}
				saved.push(website);
				completedIds.push(entry.operationId);
			} catch (error) {
				if (getStatus(error) === 401) {
					break;
				}
				logError('Queued website replay failed', error, {
					scope: 'websiteSaveSync.flush',
					url: entry.url
				});
			}
		}

		if (completedIds.length) {
			await websiteSaveQueue.removeQueuedSaves(completedIds);
		}
		return saved;
	})().finally(() => {
		flushPromise = null;
	});

	return flushPromise;
}
