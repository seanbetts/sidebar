import { beforeEach, describe, expect, it, vi } from 'vitest';
import { get } from 'svelte/store';
import { websitesStore } from '$lib/stores/websites';

const cacheState = new Map<string, unknown>();

const { websitesAPI } = vi.hoisted(() => ({
	websitesAPI: {
		list: vi.fn(),
		get: vi.fn(),
		search: vi.fn(),
		listArchived: vi.fn(),
		save: vi.fn()
	}
}));

vi.mock('$lib/services/api', () => ({ websitesAPI }));
vi.mock('$lib/utils/cache', () => ({
	getCachedData: vi.fn((key: string) => cacheState.get(key) ?? null),
	setCachedData: vi.fn((key: string, value: unknown) => cacheState.set(key, value)),
	invalidateCache: vi.fn()
}));

describe('websitesStore', () => {
	beforeEach(() => {
		cacheState.clear();
		vi.clearAllMocks();
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

		await websitesStore.load();

		expect(websitesAPI.list).toHaveBeenCalled();
		expect(get(websitesStore).items[0].id).toBe('2');
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
		websitesAPI.save.mockResolvedValue({
			success: true,
			data: { id: 'saved-1' }
		});

		const savePromise = websitesStore.saveWebsite('example.com');
		const pendingState = get(websitesStore);
		expect(pendingState.isSavingWebsite).toBe(true);
		expect(pendingState.pendingWebsite?.id.startsWith('pending-')).toBe(true);

		const result = await savePromise;
		const finalState = get(websitesStore);
		expect(result).toEqual({ success: true, id: 'saved-1' });
		expect(finalState.isSavingWebsite).toBe(false);
		expect(finalState.pendingWebsite).toBeNull();
	});
});
