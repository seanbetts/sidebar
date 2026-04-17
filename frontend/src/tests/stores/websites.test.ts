import { beforeEach, describe, expect, it, vi } from 'vitest';
import { get } from 'svelte/store';
import { websitesStore } from '$lib/stores/websites';

const cacheState = new Map<string, unknown>();

const { websitesAPI } = vi.hoisted(() => ({
	websitesAPI: {
		list: vi.fn(),
		sync: vi.fn(),
		get: vi.fn(),
		search: vi.fn(),
		listArchived: vi.fn(),
		save: vi.fn()
	}
}));

const { enqueueWebsiteSave, flushQueuedWebsiteSaves, pollUntilComplete } = vi.hoisted(() => ({
	enqueueWebsiteSave: vi.fn(),
	flushQueuedWebsiteSaves: vi.fn(),
	pollUntilComplete: vi.fn()
}));

const { user } = vi.hoisted(() => ({
	user: (() => {
		let value: { id: string } | null = { id: 'user-1' };
		const subscribers = new Set<(next: { id: string } | null) => void>();
		return {
			subscribe(run: (next: { id: string } | null) => void) {
				run(value);
				subscribers.add(run);
				return () => subscribers.delete(run);
			},
			set(next: { id: string } | null) {
				value = next;
				subscribers.forEach((run) => run(value));
			}
		};
	})()
}));

vi.mock('$lib/services/api', () => ({ websitesAPI }));
vi.mock('$lib/services/website_save_sync', () => ({
	enqueueWebsiteSave,
	flushQueuedWebsiteSaves,
	pollUntilComplete
}));
vi.mock('$lib/stores/auth', () => ({ user }));
vi.mock('$lib/utils/cache', () => ({
	getCachedData: vi.fn((key: string) => cacheState.get(key) ?? null),
	setCachedData: vi.fn((key: string, value: unknown) => cacheState.set(key, value)),
	invalidateCache: vi.fn()
}));

describe('websitesStore', () => {
	beforeEach(() => {
		cacheState.clear();
		vi.clearAllMocks();
		user.set({ id: 'user-1' });
		enqueueWebsiteSave.mockResolvedValue({
			operationId: 'queued-1',
			url: 'https://example.com',
			queuedAt: '2026-03-16T12:00:00Z'
		});
		flushQueuedWebsiteSaves.mockResolvedValue([]);
		websitesStore.reset();
	});

	it('uses cached data when available', async () => {
		const cachedItems = [
			{
				id: '1',
				title: 'Cached',
				url: '',
				domain: '',
				saved_at: null,
				published_at: null,
				pinned: false,
				updated_at: null,
				last_opened_at: null
			}
		];
		websitesAPI.list.mockResolvedValue({ items: cachedItems });
		cacheState.set('websites.list', cachedItems);

		await websitesStore.load();

		expect(websitesAPI.list).toHaveBeenCalledTimes(1);
		expect(get(websitesStore).items).toHaveLength(1);
	});

	it('loads from API when cache is empty', async () => {
		websitesAPI.list.mockResolvedValue({
			items: [
				{
					id: '2',
					title: 'Live',
					url: 'https://example.com/live',
					domain: 'example.com',
					saved_at: '2026-03-13T10:00:00Z',
					published_at: null,
					pinned: false,
					updated_at: '2026-03-13T10:00:00Z',
					last_opened_at: null
				}
			]
		});

		await websitesStore.load();

		expect(websitesAPI.list).toHaveBeenCalled();
		expect(get(websitesStore).items[0].id).toBe('2');
		expect(get(websitesStore).lastSync).toBe('2026-03-13T10:00:00Z');
	});

	it('revalidates cached websites with sync when a cached sync cursor exists', async () => {
		const cachedItems = [
			{
				id: '1',
				title: 'Cached',
				url: 'https://example.com',
				domain: 'example.com',
				saved_at: '2026-03-13T10:00:00Z',
				published_at: null,
				pinned: false,
				updated_at: '2026-03-13T10:00:00Z',
				last_opened_at: null
			}
		];
		cacheState.set('websites.list', cachedItems);
		cacheState.set('websites.lastSync', '2026-03-13T10:00:00Z');
		websitesAPI.sync.mockResolvedValue({
			applied: [],
			websites: [],
			conflicts: [],
			updates: {
				items: [
					{
						id: '1',
						title: 'Fresh',
						url: 'https://example.com',
						domain: 'example.com',
						saved_at: '2026-03-13T10:00:00Z',
						published_at: null,
						pinned: false,
						updated_at: '2026-03-14T10:00:00Z',
						deleted_at: null
					}
				]
			},
			serverUpdatedSince: '2026-03-14T10:00:00Z'
		});

		await websitesStore.load();
		await Promise.resolve();

		expect(websitesAPI.list).not.toHaveBeenCalled();
		expect(websitesAPI.sync).toHaveBeenCalledWith({
			last_sync: '2026-03-13T10:00:00Z',
			operations: []
		});
		expect(get(websitesStore).items[0].title).toBe('Fresh');
		expect(get(websitesStore).lastSync).toBe('2026-03-14T10:00:00Z');
	});

	it('revalidates loaded websites with sync deltas after initial fetch', async () => {
		websitesAPI.list.mockResolvedValue({
			items: [
				{
					id: '2',
					title: 'Live',
					url: 'https://example.com/live',
					domain: 'example.com',
					saved_at: '2026-03-13T10:00:00Z',
					published_at: null,
					pinned: false,
					updated_at: '2026-03-13T10:00:00Z',
					last_opened_at: null
				}
			]
		});
		websitesAPI.sync.mockResolvedValue({
			applied: [],
			websites: [],
			conflicts: [],
			updates: {
				items: [
					{
						id: '2',
						title: 'Live Updated',
						url: 'https://example.com/live',
						domain: 'example.com',
						saved_at: '2026-03-13T10:00:00Z',
						published_at: null,
						pinned: true,
						updated_at: '2026-03-14T12:00:00Z',
						deleted_at: null
					},
					{
						id: '3',
						title: 'New Website',
						url: 'https://example.com/new',
						domain: 'example.com',
						saved_at: '2026-03-14T12:00:00Z',
						published_at: null,
						pinned: false,
						updated_at: '2026-03-14T12:00:00Z',
						deleted_at: null
					}
				]
			},
			serverUpdatedSince: '2026-03-14T12:00:00Z'
		});

		await websitesStore.load(true);
		await websitesStore.revalidateInBackground();

		expect(websitesAPI.sync).toHaveBeenCalledWith({
			last_sync: '2026-03-13T10:00:00Z',
			operations: []
		});
		expect(get(websitesStore).items).toEqual(
			expect.arrayContaining([
				expect.objectContaining({ id: '2', title: 'Live Updated', pinned: true }),
				expect.objectContaining({ id: '3', title: 'New Website' })
			])
		);
		expect(get(websitesStore).lastSync).toBe('2026-03-14T12:00:00Z');
	});

	it('re-sorts website items after sync deltas update recency fields', async () => {
		websitesAPI.list.mockResolvedValue({
			items: [
				{
					id: '1',
					title: 'Existing Newer',
					url: 'https://example.com/1',
					domain: 'example.com',
					saved_at: '2026-03-13T10:00:00Z',
					created_at: '2026-03-10T10:00:00Z',
					published_at: null,
					pinned: false,
					updated_at: '2026-03-13T10:00:00Z',
					last_opened_at: null
				},
				{
					id: '2',
					title: 'Existing Older',
					url: 'https://example.com/2',
					domain: 'example.com',
					saved_at: '2026-03-12T10:00:00Z',
					created_at: '2026-03-09T10:00:00Z',
					published_at: null,
					pinned: false,
					updated_at: '2026-03-12T10:00:00Z',
					last_opened_at: null
				}
			]
		});
		websitesAPI.sync.mockResolvedValue({
			applied: [],
			websites: [],
			conflicts: [],
			updates: {
				items: [
					{
						id: '2',
						title: 'Existing Older Updated',
						url: 'https://example.com/2',
						domain: 'example.com',
						saved_at: '2026-03-15T10:00:00Z',
						created_at: '2026-03-09T10:00:00Z',
						published_at: null,
						pinned: false,
						updated_at: '2026-03-15T10:00:00Z',
						deleted_at: null
					},
					{
						id: '3',
						title: 'Unsaved Newer',
						url: 'https://example.com/3',
						domain: 'example.com',
						saved_at: null,
						created_at: '2026-03-14T10:00:00Z',
						published_at: null,
						pinned: false,
						updated_at: '2026-03-14T10:00:00Z',
						deleted_at: null
					},
					{
						id: '4',
						title: 'Unsaved Older',
						url: 'https://example.com/4',
						domain: 'example.com',
						saved_at: null,
						created_at: '2026-03-11T10:00:00Z',
						published_at: null,
						pinned: false,
						updated_at: '2026-03-11T10:00:00Z',
						deleted_at: null
					}
				]
			},
			serverUpdatedSince: '2026-03-15T10:00:00Z'
		});

		await websitesStore.load(true);
		await websitesStore.revalidateInBackground();

		expect(get(websitesStore).items.map((item) => item.id)).toEqual(['2', '1', '3', '4']);
	});

	it('ignores realtime updates older than current item', () => {
		websitesStore.reset();
		websitesStore.upsertFromRealtime({
			id: '1',
			title: 'New',
			url: '',
			domain: '',
			saved_at: null,
			published_at: null,
			pinned: false,
			updated_at: '2026-01-01T10:00:00Z',
			last_opened_at: null
		});

		websitesStore.upsertFromRealtime({
			id: '1',
			title: 'Old',
			url: '',
			domain: '',
			saved_at: null,
			published_at: null,
			pinned: false,
			updated_at: '2025-01-01T10:00:00Z',
			last_opened_at: null
		});

		expect(get(websitesStore).items[0].title).toBe('New');
	});

	it('updates pinned state locally', () => {
		websitesStore.upsertFromRealtime({
			id: '3',
			title: 'Pin',
			url: '',
			domain: '',
			saved_at: null,
			published_at: null,
			pinned: false,
			archived: true,
			updated_at: null,
			last_opened_at: null
		});

		websitesStore.setPinnedLocal('3', true);

		expect(get(websitesStore).items[0].pinned).toBe(true);
		expect(get(websitesStore).items[0].archived).toBe(false);
	});

	it('loads website details by id and updates active', async () => {
		websitesAPI.get.mockResolvedValue({
			id: '4',
			title: 'Detail',
			url: 'https://example.com',
			domain: 'example.com',
			content: 'Body',
			saved_at: null,
			published_at: null,
			pinned: false,
			archived: false,
			youtube_transcripts: {},
			updated_at: null,
			last_opened_at: null
		});

		await websitesStore.loadById('4');

		const state = get(websitesStore);
		expect(state.active?.id).toBe('4');
		expect(state.items[0].id).toBe('4');
	});

	it('updates transcript metadata locally', () => {
		websitesStore.upsertFromRealtime({
			id: '7',
			title: 'Video',
			url: '',
			domain: '',
			saved_at: null,
			published_at: null,
			pinned: false,
			archived: false,
			updated_at: null,
			last_opened_at: null
		});

		websitesStore.setTranscriptEntryLocal('7', 'vid123', {
			status: 'queued',
			file_id: 'file-1',
			updated_at: '2026-01-06T20:00:00Z'
		});

		expect(get(websitesStore).items[0].youtube_transcripts?.vid123?.status).toBe('queued');
	});

	it('searches via API and updates items', async () => {
		websitesAPI.search.mockResolvedValue({
			items: [
				{
					id: '5',
					title: 'Search',
					url: '',
					domain: '',
					saved_at: null,
					published_at: null,
					pinned: false,
					updated_at: null,
					last_opened_at: null
				}
			]
		});

		await websitesStore.search('query');

		expect(get(websitesStore).items[0].id).toBe('5');
	});

	it('loads archived websites and merges with active items', async () => {
		websitesStore.upsertFromRealtime({
			id: 'active-1',
			title: 'Active',
			url: 'https://active.example.com',
			domain: 'active.example.com',
			saved_at: null,
			published_at: null,
			pinned: false,
			archived: false,
			updated_at: null,
			last_opened_at: null
		});
		websitesAPI.listArchived.mockResolvedValue({
			items: [
				{
					id: 'archived-1',
					title: 'Archived',
					url: 'https://archived.example.com',
					domain: 'archived.example.com',
					saved_at: null,
					published_at: null,
					pinned: false,
					archived: true,
					updated_at: null,
					last_opened_at: null
				}
			]
		});

		await websitesStore.loadArchived();

		const state = get(websitesStore);
		expect(state.items).toHaveLength(2);
		expect(state.items.find((item) => item.id === 'active-1')?.archived).toBe(false);
		expect(state.items.find((item) => item.id === 'archived-1')?.archived).toBe(true);
	});

	it('removes items locally', () => {
		websitesStore.upsertFromRealtime({
			id: '6',
			title: 'Remove',
			url: '',
			domain: '',
			saved_at: null,
			published_at: null,
			pinned: false,
			updated_at: null,
			last_opened_at: null
		});

		websitesStore.removeLocal('6');

		expect(get(websitesStore).items).toHaveLength(0);
	});

	it('tracks pending website while saving and returns the saved id', async () => {
		websitesAPI.save.mockResolvedValue({ job_id: 'job-1', status: 'pending' });
		pollUntilComplete.mockResolvedValue({
			id: 'saved-1',
			title: 'Saved Website',
			url: 'https://example.com',
			domain: 'example.com',
			content: 'Hello',
			source: 'readability',
			url_full: 'https://example.com',
			saved_at: '2026-03-13T10:00:00Z',
			published_at: null,
			pinned: false,
			archived: false,
			updated_at: '2026-03-13T10:00:00Z',
			last_opened_at: null
		});

		const savePromise = websitesStore.saveWebsite('example.com');
		const pendingState = get(websitesStore);
		expect(pendingState.isSavingWebsite).toBe(true);
		expect(pendingState.pendingWebsite?.id.startsWith('pending-')).toBe(true);

		const result = await savePromise;
		const finalState = get(websitesStore);
		expect(result).toMatchObject({
			success: true,
			id: 'saved-1',
			website: {
				id: 'saved-1',
				title: 'Saved Website'
			}
		});
		expect(finalState.isSavingWebsite).toBe(false);
		expect(finalState.pendingWebsite).toBeNull();
		expect(finalState.items[0]).toMatchObject({
			id: 'saved-1',
			title: 'Saved Website',
			url: 'https://example.com'
		});
		expect(pollUntilComplete).toHaveBeenCalledWith('job-1');
	});

	it('treats YouTube URLs as regular website saves', async () => {
		websitesAPI.save.mockResolvedValue({ job_id: 'job-yt', status: 'pending' });
		pollUntilComplete.mockResolvedValue({
			id: 'saved-youtube',
			title: 'Video',
			url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
			domain: 'youtube.com',
			content: 'Transcript',
			source: 'youtube',
			url_full: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
			saved_at: '2026-03-13T10:00:00Z',
			published_at: null,
			pinned: false,
			archived: false,
			updated_at: '2026-03-13T10:00:00Z',
			last_opened_at: null
		});

		const result = await websitesStore.saveWebsite('https://www.youtube.com/watch?v=dQw4w9WgXcQ');

		expect(websitesAPI.save).toHaveBeenCalledWith('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
		expect(result).toMatchObject({
			success: true,
			id: 'saved-youtube',
			website: {
				id: 'saved-youtube'
			}
		});
		expect(get(websitesStore).saveError).toBeNull();
	});

	it('queues website saves while signed out instead of reporting a completed save', async () => {
		user.set(null);

		const result = await websitesStore.saveWebsite('example.com');

		expect(enqueueWebsiteSave).toHaveBeenCalledWith('https://example.com/');
		expect(websitesAPI.save).not.toHaveBeenCalled();
		expect(result).toMatchObject({
			success: true,
			queued: true,
			message: 'Website queued until you sign in again.'
		});
		expect(get(websitesStore).items).toEqual([]);
		expect(get(websitesStore).saveError).toBeNull();
	});

	it('queues website saves after an unauthorized response', async () => {
		const error = new Error('Unauthorized') as Error & { status?: number };
		error.status = 401;
		websitesAPI.save.mockRejectedValue(error);

		const result = await websitesStore.saveWebsite('https://example.com/private');

		expect(websitesAPI.save).toHaveBeenCalledWith('https://example.com/private');
		expect(enqueueWebsiteSave).toHaveBeenCalledWith('https://example.com/private');
		expect(result).toMatchObject({
			success: true,
			queued: true,
			message: 'Website queued until you sign in again.'
		});
		expect(get(websitesStore).items).toEqual([]);
		expect(get(websitesStore).saveError).toBeNull();
	});

	it('flushes queued website saves into the store when replay succeeds', async () => {
		flushQueuedWebsiteSaves.mockResolvedValue([
			{
				id: 'saved-queued-1',
				title: 'Queued Website',
				url: 'https://example.com/queued',
				domain: 'example.com',
				content: 'Queued content',
				source: 'readability',
				url_full: 'https://example.com/queued',
				saved_at: '2026-03-16T12:10:00Z',
				published_at: null,
				pinned: false,
				archived: false,
				youtube_transcripts: {},
				updated_at: '2026-03-16T12:10:00Z',
				last_opened_at: null
			}
		]);

		const flushed = await websitesStore.flushQueuedSaves();

		expect(flushQueuedWebsiteSaves).toHaveBeenCalledTimes(1);
		expect(flushed).toHaveLength(1);
		expect(get(websitesStore).items[0]).toMatchObject({
			id: 'saved-queued-1',
			title: 'Queued Website'
		});
	});

	it('can set a saved website as active without refetching', async () => {
		const website = {
			id: 'saved-active',
			title: 'Saved Active',
			url: 'https://example.com/active',
			domain: 'example.com',
			content: 'Saved active content',
			source: 'readability',
			url_full: 'https://example.com/active',
			saved_at: '2026-03-13T10:10:00Z',
			published_at: null,
			pinned: false,
			archived: false,
			youtube_transcripts: {},
			updated_at: '2026-03-13T10:10:00Z',
			last_opened_at: null
		};

		websitesStore.setActiveWebsite(website);

		expect(get(websitesStore).active).toMatchObject({
			id: 'saved-active',
			content: 'Saved active content'
		});
	});

	it('preserves freshly saved websites during stale reloads', async () => {
		websitesAPI.save.mockResolvedValue({ job_id: 'job-fresh', status: 'pending' });
		pollUntilComplete.mockResolvedValue({
			id: 'saved-2',
			title: 'Fresh Save',
			url: 'https://example.com/fresh',
			domain: 'example.com',
			content: 'Fresh content',
			source: 'readability',
			url_full: 'https://example.com/fresh',
			saved_at: '2026-03-13T10:05:00Z',
			published_at: null,
			pinned: false,
			archived: false,
			updated_at: '2026-03-13T10:05:00Z',
			last_opened_at: null
		});
		websitesAPI.list.mockResolvedValue({
			items: [
				{
					id: 'older-1',
					title: 'Older',
					url: 'https://example.com/older',
					domain: 'example.com',
					saved_at: '2026-03-12T10:00:00Z',
					published_at: null,
					pinned: false,
					archived: false,
					updated_at: '2026-03-12T10:00:00Z',
					last_opened_at: null
				}
			]
		});

		await websitesStore.saveWebsite('https://example.com/fresh');
		await websitesStore.load(true);

		expect(get(websitesStore).items.map((item) => item.id)).toEqual(['saved-2', 'older-1']);
	});
});
