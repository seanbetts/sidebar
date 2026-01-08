/**
 * Conversation list store with timeline grouping
 */
import { get, writable, derived } from 'svelte/store';
import type { Conversation } from '$lib/types/history';
import { conversationsAPI } from '$lib/services/api';
import { getCachedData, invalidateCache, isCacheStale, setCachedData } from '$lib/utils/cache';
import { dispatchCacheEvent } from '$lib/utils/cacheEvents';
import { logError } from '$lib/utils/errorHandling';

const CACHE_KEY = 'conversations.list';
const CACHE_TTL = 10 * 60 * 1000;
const CACHE_VERSION = '1.0';

interface ConversationListState {
	conversations: Conversation[];
	loading: boolean;
	searchQuery: string;
	generatingTitleIds: Set<string>;
	loaded: boolean;
}

function createConversationListStore() {
	const { subscribe, update } = writable<ConversationListState>({
		conversations: [],
		loading: false,
		searchQuery: '',
		generatingTitleIds: new Set(),
		loaded: false
	});

	return {
		subscribe,

		async load(force: boolean = false) {
			const currentState = get({ subscribe });
			if (!force && currentState.searchQuery) {
				return;
			}

			if (!force) {
				const cached = getCachedData<Conversation[]>(CACHE_KEY, {
					ttl: CACHE_TTL,
					version: CACHE_VERSION
				});
				if (cached) {
					update((state) => ({
						...state,
						conversations: cached,
						loading: false,
						loaded: true
					}));
					if (isCacheStale(CACHE_KEY, CACHE_TTL)) {
						this.revalidateInBackground();
					}
					return;
				}
				if (currentState.loaded) {
					return;
				}
			}
			update((state) => ({ ...state, loading: true }));
			try {
				const conversations = await conversationsAPI.list();
				setCachedData(CACHE_KEY, conversations, { ttl: CACHE_TTL, version: CACHE_VERSION });
				update((state) => ({ ...state, conversations, loading: false, loaded: true }));
			} catch (error) {
				logError('Failed to load conversations', error, { scope: 'conversationsStore.load' });
				update((state) => ({ ...state, loading: false, loaded: false }));
			}
		},

		async refresh() {
			await this.load(true);
		},

		async revalidateInBackground() {
			try {
				const conversations = await conversationsAPI.list();
				setCachedData(CACHE_KEY, conversations, { ttl: CACHE_TTL, version: CACHE_VERSION });
				update((state) => ({ ...state, conversations }));
			} catch (error) {
				logError('Background revalidation failed', error, {
					scope: 'conversationsStore.revalidateInBackground'
				});
			}
		},

		async search(query: string) {
			update((state) => ({ ...state, searchQuery: query, loading: true }));
			try {
				const conversations = query
					? await conversationsAPI.search(query)
					: await conversationsAPI.list();
				update((state) => ({ ...state, conversations, loading: false, loaded: true }));
			} catch (error) {
				logError('Failed to search conversations', error, {
					scope: 'conversationsStore.search',
					query
				});
				update((state) => ({ ...state, loading: false, loaded: false }));
			}
		},

		async deleteConversation(id: string) {
			try {
				await conversationsAPI.delete(id);
				update((state) => ({
					...state,
					conversations: state.conversations.filter((c) => c.id !== id)
				}));
				invalidateCache(CACHE_KEY);
				dispatchCacheEvent('conversation.deleted');
			} catch (error) {
				logError('Failed to delete conversation', error, {
					scope: 'conversationsStore.deleteConversation',
					conversationId: id
				});
			}
		},

		/**
		 * Add a new conversation to the list without full refresh
		 * @param conversation Conversation to prepend.
		 */
		addConversation(conversation: Conversation) {
			update((state) => ({
				...state,
				conversations: [conversation, ...state.conversations]
			}));
			const nextState = get({ subscribe });
			if (!nextState.searchQuery) {
				setCachedData(CACHE_KEY, nextState.conversations, {
					ttl: CACHE_TTL,
					version: CACHE_VERSION
				});
			}
		},

		/**
		 * Update conversation metadata (message count, preview) without full refresh
		 * @param id Conversation id to update.
		 * @param updates Partial metadata updates.
		 * @param updates.messageCount Message count value.
		 * @param updates.firstMessage Preview snippet.
		 * @param updates.updatedAt Updated timestamp (ISO).
		 */
		updateConversationMetadata(
			id: string,
			updates: { messageCount?: number; firstMessage?: string; updatedAt?: string }
		) {
			update((state) => ({
				...state,
				conversations: state.conversations.map((c) => (c.id === id ? { ...c, ...updates } : c))
			}));
			const nextState = get({ subscribe });
			if (!nextState.searchQuery) {
				setCachedData(CACHE_KEY, nextState.conversations, {
					ttl: CACHE_TTL,
					version: CACHE_VERSION
				});
			}
		},

		/**
		 * Mark a conversation as generating title
		 * @param id Conversation id to update.
		 * @param generating Whether title generation is in progress.
		 */
		setGeneratingTitle(id: string, generating: boolean) {
			update((state) => {
				const newGeneratingIds = new Set(state.generatingTitleIds);
				if (generating) {
					newGeneratingIds.add(id);
				} else {
					newGeneratingIds.delete(id);
				}
				return {
					...state,
					generatingTitleIds: newGeneratingIds
				};
			});
		},

		/**
		 * Update a single conversation's title without refreshing the entire list
		 * @param id Conversation id to update.
		 * @param title New title value.
		 * @param titleGenerated Whether the title was model-generated.
		 */
		updateConversationTitle(id: string, title: string, titleGenerated: boolean = true) {
			update((state) => {
				const newGeneratingIds = new Set(state.generatingTitleIds);
				newGeneratingIds.delete(id);
				return {
					...state,
					generatingTitleIds: newGeneratingIds,
					conversations: state.conversations.map((c) =>
						c.id === id ? { ...c, title, titleGenerated } : c
					)
				};
			});
			const nextState = get({ subscribe });
			if (!nextState.searchQuery) {
				setCachedData(CACHE_KEY, nextState.conversations, {
					ttl: CACHE_TTL,
					version: CACHE_VERSION
				});
			}
		}
	};
}

export const conversationListStore = createConversationListStore();

// Derived store for timeline grouping
export const groupedConversations = derived(conversationListStore, ($store) => {
	const now = new Date();
	const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
	const yesterday = new Date(today);
	yesterday.setDate(yesterday.getDate() - 1);
	const lastWeek = new Date(today);
	lastWeek.setDate(lastWeek.getDate() - 7);
	const lastMonth = new Date(today);
	lastMonth.setDate(lastMonth.getDate() - 30);

	const groups = {
		today: [] as Conversation[],
		yesterday: [] as Conversation[],
		lastWeek: [] as Conversation[],
		lastMonth: [] as Conversation[],
		older: [] as Conversation[]
	};

	$store.conversations.forEach((conv) => {
		const date = new Date(conv.updatedAt);
		if (date >= today) groups.today.push(conv);
		else if (date >= yesterday) groups.yesterday.push(conv);
		else if (date >= lastWeek) groups.lastWeek.push(conv);
		else if (date >= lastMonth) groups.lastMonth.push(conv);
		else groups.older.push(conv);
	});

	return groups;
});

// Track current conversation
export const currentConversationId = writable<string | null>(null);
