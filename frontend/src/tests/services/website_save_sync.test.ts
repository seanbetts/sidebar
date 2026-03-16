import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { websitesAPI } = vi.hoisted(() => ({
	websitesAPI: {
		save: vi.fn()
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

describe('website_save_sync service', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		setOnline(true);
		websiteSaveQueue.enqueueSave.mockResolvedValue({
			operationId: 'queued-1',
			url: 'https://example.com',
			queuedAt: '2026-03-16T12:00:00Z'
		});
		websiteSaveQueue.listQueuedSaves.mockResolvedValue([]);
		websiteSaveQueue.removeQueuedSaves.mockResolvedValue(undefined);
		websitesAPI.save.mockResolvedValue({
			success: true,
			website: {
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
				youtube_transcripts: {},
				updated_at: '2026-03-16T12:05:00Z',
				last_opened_at: null
			}
		});
	});

	afterEach(() => {
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
			.mockResolvedValueOnce({
				success: true,
				website: {
					id: 'saved-1',
					title: 'One',
					url: 'https://example.com/one',
					domain: 'example.com',
					content: 'One',
					source: 'readability',
					url_full: 'https://example.com/one',
					saved_at: '2026-03-16T12:05:00Z',
					published_at: null,
					pinned: false,
					archived: false,
					youtube_transcripts: {},
					updated_at: '2026-03-16T12:05:00Z',
					last_opened_at: null
				}
			})
			.mockResolvedValueOnce({
				success: true,
				website: {
					id: 'saved-2',
					title: 'Two',
					url: 'https://example.com/two',
					domain: 'example.com',
					content: 'Two',
					source: 'readability',
					url_full: 'https://example.com/two',
					saved_at: '2026-03-16T12:06:00Z',
					published_at: null,
					pinned: false,
					archived: false,
					youtube_transcripts: {},
					updated_at: '2026-03-16T12:06:00Z',
					last_opened_at: null
				}
			});
		const { flushQueuedWebsiteSaves } = await loadWebsiteSaveSync();

		const saved = await flushQueuedWebsiteSaves();

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
});
