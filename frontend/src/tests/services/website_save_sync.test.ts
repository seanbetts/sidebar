import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { websitesAPI } = vi.hoisted(() => ({
	websitesAPI: {
		save: vi.fn(),
		jobStatus: vi.fn()
	}
}));

vi.mock('$lib/services/api', () => ({
	websitesAPI
}));

const { websiteSaveQueue } = vi.hoisted(() => ({
	websiteSaveQueue: {
		enqueueSave: vi.fn(),
		listQueuedSaves: vi.fn(),
		removeQueuedSaves: vi.fn()
	}
}));

vi.mock('$lib/stores/website_save_queue', () => ({
	websiteSaveQueue
}));

const originalNavigator = globalThis.navigator;

const setOnline = (isOnline: boolean) => {
	Object.defineProperty(globalThis, 'navigator', {
		value: { onLine: isOnline },
		configurable: true
	});
};

const loadWebsiteSaveSync = async () => {
	vi.resetModules();
	return import('$lib/services/website_save_sync');
};

const COMPLETED_WEBSITE = {
	id: 'saved-1',
	title: 'Saved',
	url: 'https://example.com',
	domain: 'example.com',
	content: 'Body',
	source: 'readability',
	url_full: 'https://example.com',
	saved_at: '2026-03-16T12:05:00Z',
	published_at: null,
	pinned: false,
	archived: false,
	updated_at: '2026-03-16T12:05:00Z',
	last_opened_at: null
};

describe('website_save_sync service', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.useFakeTimers();
		setOnline(true);
		websiteSaveQueue.enqueueSave.mockResolvedValue({
			operationId: 'queued-1',
			url: 'https://example.com',
			queuedAt: '2026-03-16T12:00:00Z'
		});
		websiteSaveQueue.listQueuedSaves.mockResolvedValue([]);
		websiteSaveQueue.removeQueuedSaves.mockResolvedValue(undefined);
		websitesAPI.save.mockResolvedValue({
			job_id: 'job-1',
			status: 'pending'
		});
		websitesAPI.jobStatus.mockResolvedValue({
			job_id: 'job-1',
			status: 'completed',
			website: COMPLETED_WEBSITE
		});
	});

	afterEach(() => {
		vi.useRealTimers();
		Object.defineProperty(globalThis, 'navigator', {
			value: originalNavigator,
			configurable: true
		});
	});

	it('enqueues normalized website save requests', async () => {
		const { enqueueWebsiteSave } = await loadWebsiteSaveSync();

		const queued = await enqueueWebsiteSave('https://example.com');

		expect(queued).toMatchObject({
			operationId: 'queued-1',
			url: 'https://example.com'
		});
		expect(websiteSaveQueue.enqueueSave).toHaveBeenCalledWith('https://example.com');
	});

	it('does not flush queued website saves while offline', async () => {
		setOnline(false);
		const { flushQueuedWebsiteSaves } = await loadWebsiteSaveSync();

		await expect(flushQueuedWebsiteSaves()).resolves.toEqual([]);
		expect(websiteSaveQueue.listQueuedSaves).not.toHaveBeenCalled();
		expect(websitesAPI.save).not.toHaveBeenCalled();
	});

	it('flushes queued website saves and removes successful entries', async () => {
		websiteSaveQueue.listQueuedSaves.mockResolvedValue([
			{
				operationId: 'queued-1',
				url: 'https://example.com/one',
				queuedAt: '2026-03-16T12:00:00Z'
			},
			{
				operationId: 'queued-2',
				url: 'https://example.com/two',
				queuedAt: '2026-03-16T12:01:00Z'
			}
		]);
		websitesAPI.save
			.mockResolvedValueOnce({ job_id: 'job-1', status: 'pending' })
			.mockResolvedValueOnce({ job_id: 'job-2', status: 'pending' });
		websitesAPI.jobStatus
			.mockResolvedValueOnce({
				job_id: 'job-1',
				status: 'completed',
				website: {
					...COMPLETED_WEBSITE,
					id: 'saved-1',
					title: 'One',
					url: 'https://example.com/one',
					content: 'One',
					url_full: 'https://example.com/one'
				}
			})
			.mockResolvedValueOnce({
				job_id: 'job-2',
				status: 'completed',
				website: {
					...COMPLETED_WEBSITE,
					id: 'saved-2',
					title: 'Two',
					url: 'https://example.com/two',
					content: 'Two',
					url_full: 'https://example.com/two',
					saved_at: '2026-03-16T12:06:00Z',
					updated_at: '2026-03-16T12:06:00Z'
				}
			});
		const { flushQueuedWebsiteSaves } = await loadWebsiteSaveSync();

		const flushPromise = flushQueuedWebsiteSaves();
		// Advance past two poll intervals (10s each)
		await vi.advanceTimersByTimeAsync(10_000);
		await vi.advanceTimersByTimeAsync(10_000);
		const saved = await flushPromise;

		expect(saved.map((item) => item.id)).toEqual(['saved-1', 'saved-2']);
		expect(websitesAPI.save).toHaveBeenNthCalledWith(1, 'https://example.com/one');
		expect(websitesAPI.save).toHaveBeenNthCalledWith(2, 'https://example.com/two');
		expect(websiteSaveQueue.removeQueuedSaves).toHaveBeenCalledWith(['queued-1', 'queued-2']);
	});

	it('keeps queued entries when replay becomes unauthorized', async () => {
		websiteSaveQueue.listQueuedSaves.mockResolvedValue([
			{
				operationId: 'queued-1',
				url: 'https://example.com/one',
				queuedAt: '2026-03-16T12:00:00Z'
			}
		]);
		const unauthorized = new Error('Unauthorized') as Error & { status?: number };
		unauthorized.status = 401;
		websitesAPI.save.mockRejectedValue(unauthorized);
		const { flushQueuedWebsiteSaves } = await loadWebsiteSaveSync();

		await expect(flushQueuedWebsiteSaves()).resolves.toEqual([]);
		expect(websiteSaveQueue.removeQueuedSaves).not.toHaveBeenCalled();
	});

	it('polls until job completes', async () => {
		websitesAPI.jobStatus
			.mockResolvedValueOnce({ job_id: 'job-1', status: 'processing' })
			.mockResolvedValueOnce({
				job_id: 'job-1',
				status: 'completed',
				website: COMPLETED_WEBSITE
			});
		const { pollUntilComplete } = await loadWebsiteSaveSync();

		const pollPromise = pollUntilComplete('job-1');
		await vi.advanceTimersByTimeAsync(10_000);
		await vi.advanceTimersByTimeAsync(15_000);
		const result = await pollPromise;

		expect(result).toMatchObject({ id: 'saved-1' });
		expect(websitesAPI.jobStatus).toHaveBeenCalledTimes(2);
	});

	it('throws when a job fails', async () => {
		websitesAPI.jobStatus.mockResolvedValueOnce({
			job_id: 'job-1',
			status: 'failed',
			error: { message: 'Content extraction failed' }
		});
		const { pollUntilComplete } = await loadWebsiteSaveSync();

		const pollPromise = pollUntilComplete('job-1').catch((e: Error) => e);
		await vi.advanceTimersByTimeAsync(10_000);
		const error = await pollPromise;

		expect(error).toBeInstanceOf(Error);
		expect((error as Error).message).toBe('Content extraction failed');
	});
});
