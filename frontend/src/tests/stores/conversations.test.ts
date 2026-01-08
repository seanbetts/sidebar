import { beforeEach, describe, expect, it, vi } from 'vitest';
import { get } from 'svelte/store';
import { conversationListStore } from '$lib/stores/conversations';

const cacheState = new Map<string, unknown>();

const { conversationsAPI } = vi.hoisted(() => ({
	conversationsAPI: {
		list: vi.fn(),
		search: vi.fn(),
		delete: vi.fn()
	}
}));

vi.mock('$lib/services/api', () => ({
	conversationsAPI
}));

vi.mock('$lib/utils/cache', () => ({
	getCachedData: vi.fn((key: string) => cacheState.get(key) ?? null),
	setCachedData: vi.fn((key: string, value: unknown) => cacheState.set(key, value)),
	isCacheStale: vi.fn(() => false),
	invalidateCache: vi.fn()
}));

vi.mock('$lib/utils/cacheEvents', () => ({
	dispatchCacheEvent: vi.fn()
}));

describe('conversationListStore', () => {
	beforeEach(() => {
		cacheState.clear();
		vi.clearAllMocks();
	});

	it('loads conversations from cache when available', async () => {
		const cached = [
			{
				id: '1',
				title: 'Cached',
				titleGenerated: false,
				createdAt: new Date().toISOString(),
				updatedAt: new Date().toISOString(),
				messageCount: 1
			}
		];
		cacheState.set('conversations.list', cached);

		await conversationListStore.load();

		const state = get(conversationListStore);
		expect(state.conversations).toEqual(cached);
		expect(conversationsAPI.list).not.toHaveBeenCalled();
	});

	it('fetches conversations when cache is empty', async () => {
		const remote = [
			{
				id: '2',
				title: 'Remote',
				titleGenerated: true,
				createdAt: new Date().toISOString(),
				updatedAt: new Date().toISOString(),
				messageCount: 2
			}
		];
		conversationsAPI.list.mockResolvedValue(remote);

		await conversationListStore.load(true);

		const state = get(conversationListStore);
		expect(conversationsAPI.list).toHaveBeenCalled();
		expect(state.conversations).toEqual(remote);
	});

	it('adds conversation locally', () => {
		conversationListStore.addConversation({
			id: '3',
			title: 'New',
			titleGenerated: false,
			createdAt: new Date().toISOString(),
			updatedAt: new Date().toISOString(),
			messageCount: 0
		});

		expect(get(conversationListStore).conversations[0].id).toBe('3');
	});

	it('updates conversation title', () => {
		conversationListStore.addConversation({
			id: '4',
			title: 'Old',
			titleGenerated: false,
			createdAt: new Date().toISOString(),
			updatedAt: new Date().toISOString(),
			messageCount: 0
		});

		conversationListStore.updateConversationTitle('4', 'New', true);

		expect(get(conversationListStore).conversations[0].title).toBe('New');
	});

	it('searches conversations with API', async () => {
		conversationsAPI.search.mockResolvedValue([
			{
				id: '5',
				title: 'Found',
				titleGenerated: false,
				createdAt: new Date().toISOString(),
				updatedAt: new Date().toISOString(),
				messageCount: 1
			}
		]);

		await conversationListStore.search('hello');

		expect(conversationsAPI.search).toHaveBeenCalledWith('hello');
		expect(get(conversationListStore).conversations).toHaveLength(1);
	});

	it('deletes conversations and updates list', async () => {
		conversationsAPI.delete.mockResolvedValue(undefined);
		conversationListStore.addConversation({
			id: '6',
			title: 'Delete me',
			titleGenerated: false,
			createdAt: new Date().toISOString(),
			updatedAt: new Date().toISOString(),
			messageCount: 0
		});

		await conversationListStore.deleteConversation('6');

		expect(conversationsAPI.delete).toHaveBeenCalledWith('6');
		expect(get(conversationListStore).conversations.some((conv) => conv.id === '6')).toBe(false);
	});

	it('updates conversation metadata locally', () => {
		conversationListStore.addConversation({
			id: '7',
			title: 'Meta',
			titleGenerated: false,
			createdAt: new Date().toISOString(),
			updatedAt: new Date().toISOString(),
			messageCount: 1
		});

		conversationListStore.updateConversationMetadata('7', {
			messageCount: 3,
			firstMessage: 'Preview',
			updatedAt: new Date().toISOString()
		});

		expect(get(conversationListStore).conversations[0].messageCount).toBe(3);
	});

	it('toggles generating title state', () => {
		conversationListStore.setGeneratingTitle('8', true);
		expect(get(conversationListStore).generatingTitleIds.has('8')).toBe(true);

		conversationListStore.setGeneratingTitle('8', false);
		expect(get(conversationListStore).generatingTitleIds.has('8')).toBe(false);
	});

	it('revalidates conversations in background', async () => {
		conversationsAPI.list.mockResolvedValue([
			{
				id: '9',
				title: 'BG',
				titleGenerated: false,
				createdAt: new Date().toISOString(),
				updatedAt: new Date().toISOString(),
				messageCount: 1
			}
		]);

		await conversationListStore.revalidateInBackground();

		expect(get(conversationListStore).conversations).toHaveLength(1);
	});
});
