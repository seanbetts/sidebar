import { websitesAPI } from '$lib/services/api';
import { websiteSaveQueue, type QueuedWebsiteSave } from '$lib/stores/website_save_queue';
import { logError } from '$lib/utils/errorHandling';

type JobStatusPayload = Awaited<ReturnType<typeof websitesAPI.jobStatus>>;
type SavedWebsiteDetail = NonNullable<JobStatusPayload['website']>;

let flushPromise: Promise<SavedWebsiteDetail[]> | null = null;

const isOnline = () => typeof navigator !== 'undefined' && navigator.onLine;

const getStatus = (error: unknown): number | null => {
	if (!error || typeof error !== 'object') return null;
	const status = (error as { status?: unknown }).status;
	return typeof status === 'number' ? status : null;
};

const POLL_INTERVALS = [10, 15, 20, 30, 45, 60, 60];
const POLL_MAX_DURATION_MS = 5 * 60 * 1000;

/**
 * Poll a save job until it completes or times out.
 */
export async function pollUntilComplete(jobId: string): Promise<SavedWebsiteDetail | null> {
	const start = Date.now();
	let attempt = 0;
	while (Date.now() - start < POLL_MAX_DURATION_MS) {
		const interval = POLL_INTERVALS[Math.min(attempt, POLL_INTERVALS.length - 1)];
		await new Promise((r) => setTimeout(r, interval * 1000));
		attempt++;
		let jobFailed = false;
		try {
			const status = await websitesAPI.jobStatus(jobId);
			if (status.status === 'completed' && status.website) return status.website;
			if (status.status === 'failed') {
				jobFailed = true;
				throw new Error(status.error?.message ?? 'Save failed');
			}
		} catch (error) {
			if (jobFailed) throw error;
			// Swallow transient network errors and keep polling.
		}
	}
	throw new Error('Save timed out');
}

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
				const { job_id } = await websitesAPI.save(entry.url);
				const website = await pollUntilComplete(job_id);
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
