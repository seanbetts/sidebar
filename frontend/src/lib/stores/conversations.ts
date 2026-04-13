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
const LAST_SYNC_CACHE_KEY = 'conversations.lastSync';
const CACHE_TTL = 10 * 60 * 1000;
const CACHE_VERSION = '1.0';

const mergeSyncCursor = (current: string | null, candidate: string | null): string | null => {
	if (!current) return candidate;
	if (!candidate) return current;
	const currentTime = new Date(current).getTime();
	const candidateTime = new Date(candidate).getTime();
	if (!Number.isFinite(currentTime)) return candidate;
	if (!Number.isFinite(candidateTime)) return current;
	return candidateTime > currentTime ? candidate : current;
};

const deriveSyncCursor = (conversations: Conversation[]): string | null =>
	conversations.reduce<string | null>(
		(cursor, conversation) => mergeSyncCursor(cursor, conversation.updatedAt ?? null),
		null
	);

const persistConversationCache = (conversations: Conversation[], lastSync: string | null) => {
	setCachedData(CACHE_KEY, conversations, { ttl: CACHE_TTL, version: CACHE_VERSION });
	if (lastSync) {
		setCachedData(LAST_SYNC_CACHE_KEY, lastSync, { ttl: CACHE_TTL, version: CACHE_VERSION });
	}
};

interface ConversationListState {
	conversations: Conversation[];
	loading: boolean;
	searchQuery: string;
	generatingTitleIds: Set<string>;
	loaded: boolean;
	lastSync: string | null;
}

function createConversationListStore() {
	const { subscribe, update } = writable<ConversationListState>({
		conversations: [],
		loading: false,
		searchQuery: '',
		generatingTitleIds: new Set(),
		loaded: false,
		lastSync: null
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
					const cachedLastSync =
						getCachedData<string>(LAST_SYNC_CACHE_KEY, {
							ttl: CACHE_TTL,
							version: CACHE_VERSION
						}) ?? deriveSyncCursor(cached);
					persistConversationCache(cached, cachedLastSync);
					update((state) => ({
						...state,
						conversations: cached,
						loading: false,
						loaded: true,
						lastSync: mergeSyncCursor(state.lastSync, cachedLastSync)
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
				const nextLastSync = mergeSyncCursor(
					currentState.lastSync,
					deriveSyncCursor(conversations)
				);
				persistConversationCache(conversations, nextLastSync);
				update((state) => ({
					...state,
					conversations,
					loading: false,
					loaded: true,
					lastSync: nextLastSync
				}));
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
				const currentState = get({ subscribe });
				if (currentState.lastSync) {
					const deltaConversations = await conversationsAPI.list(currentState.lastSync);
					const nextLastSync = mergeSyncCursor(
						currentState.lastSync,
						deriveSyncCursor(deltaConversations)
					);
					update((state) => {
						const byId = new Map(
							state.conversations.map((conversation) => [conversation.id, conversation])
						);
						for (const conversation of deltaConversations) {
							if (conversation.isArchived) {
								byId.delete(conversation.id);
								continue;
							}
							const existing = byId.get(conversation.id);
							byId.set(conversation.id, existing ? { ...existing, ...conversation } : conversation);
						}
						const orderedExisting = state.conversations
							.map((conversation) => byId.get(conversation.id))
							.filter((conversation): conversation is Conversation => Boolean(conversation));
						const newConversations = deltaConversations.filter(
							(conversation) =>
								!conversation.isArchived &&
								!state.conversations.some((existing) => existing.id === conversation.id)
						);
						const mergedConversations = [...newConversations, ...orderedExisting];
						persistConversationCache(mergedConversations, nextLastSync);
						return {
							...state,
							conversations: mergedConversations,
							lastSync: nextLastSync
						};
					});
					return;
				}

				const conversations = await conversationsAPI.list();
				const nextLastSync = mergeSyncCursor(
					currentState.lastSync,
					deriveSyncCursor(conversations)
				);
				persistConversationCache(conversations, nextLastSync);
				update((state) => ({ ...state, conversations, lastSync: nextLastSync }));
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
				invalidateCache(LAST_SYNC_CACHE_KEY);
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
				persistConversationCache(
					nextState.conversations,
					mergeSyncCursor(nextState.lastSync, conversation.updatedAt ?? null)
				);
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
				persistConversationCache(
					nextState.conversations,
					mergeSyncCursor(nextState.lastSync, updates.updatedAt ?? null)
				);
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
		 * @param updatedAt Updated timestamp from the backend, when provided.
		 */
		updateConversationTitle(
			id: string,
			title: string,
			titleGenerated: boolean = true,
			updatedAt?: string
		) {
			update((state) => {
				const newGeneratingIds = new Set(state.generatingTitleIds);
				newGeneratingIds.delete(id);
				return {
					...state,
					generatingTitleIds: newGeneratingIds,
					conversations: state.conversations.map((c) =>
						c.id === id ? { ...c, title, titleGenerated, updatedAt: updatedAt ?? c.updatedAt } : c
					)
				};
			});
			const nextState = get({ subscribe });
			if (!nextState.searchQuery) {
				persistConversationCache(
					nextState.conversations,
					mergeSyncCursor(nextState.lastSync, updatedAt ?? null)
				);
			}
		},

		reset() {
			invalidateCache(CACHE_KEY);
			invalidateCache(LAST_SYNC_CACHE_KEY);
			update(() => ({
				conversations: [],
				loading: false,
				searchQuery: '',
				generatingTitleIds: new Set(),
				loaded: false,
				lastSync: null
			}));
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
