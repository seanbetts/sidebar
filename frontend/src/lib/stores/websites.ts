import { get, writable } from 'svelte/store';
import { websitesAPI } from '$lib/services/api';
import { getCachedData, invalidateCache, setCachedData } from '$lib/utils/cache';
import { logError } from '$lib/utils/errorHandling';

const CACHE_KEY = 'websites.list';
const CACHE_TTL = 15 * 60 * 1000;
const CACHE_VERSION = '1.1';

export interface WebsiteItem {
	id: string;
	title: string;
	url: string;
	domain: string;
	saved_at: string | null;
	published_at: string | null;
	pinned: boolean;
	pinned_order?: number | null;
	archived?: boolean;
	youtube_transcripts?: Record<string, WebsiteTranscriptEntry>;
	updated_at: string | null;
	last_opened_at: string | null;
}

export interface WebsiteTranscriptEntry {
	status?: string;
	file_id?: string;
	updated_at?: string;
	error?: string;
}

export interface WebsiteDetail extends WebsiteItem {
	content: string;
	source: string | null;
	url_full: string | null;
}

const isWebsiteItem = (value: unknown): value is WebsiteItem => {
	if (!value || typeof value !== 'object') return false;
	const item = value as Record<string, unknown>;
	return (
		typeof item.id === 'string' &&
		typeof item.title === 'string' &&
		typeof item.url === 'string' &&
		typeof item.domain === 'string'
	);
};

const isWebsiteDetail = (value: unknown): value is WebsiteDetail => {
	if (!isWebsiteItem(value)) return false;
	const item = value as unknown as Record<string, unknown>;
	return typeof item.content === 'string';
};

const buildWebsiteSummary = (data: WebsiteDetail): WebsiteItem => ({
	id: data.id,
	title: data.title,
	url: data.url,
	domain: data.domain,
	saved_at: data.saved_at,
	published_at: data.published_at,
	pinned: data.pinned ?? false,
	pinned_order: data.pinned_order ?? null,
	archived: data.archived ?? false,
	youtube_transcripts: data.youtube_transcripts ?? {},
	updated_at: data.updated_at,
	last_opened_at: data.last_opened_at
});

const extractWebsiteItems = (value: unknown): WebsiteItem[] => {
	const data = value as { items?: unknown[] };
	if (Array.isArray(data?.items)) {
		return data.items.filter(isWebsiteItem);
	}
	return [];
};

function createWebsitesStore() {
	const { subscribe, set, update } = writable<{
		items: WebsiteItem[];
		loading: boolean;
		error: string | null;
		active: WebsiteDetail | null;
		loadingDetail: boolean;
		searchQuery: string;
		loaded: boolean;
	}>({
		items: [],
		loading: false,
		error: null,
		active: null,
		loadingDetail: false,
		searchQuery: '',
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
				const cached = getCachedData<WebsiteItem[]>(CACHE_KEY, {
					ttl: CACHE_TTL,
					version: CACHE_VERSION
				});
				if (cached) {
					update((state) => ({
						...state,
						items: cached,
						loading: false,
						error: null,
						searchQuery: '',
						loaded: true
					}));
					this.revalidateInBackground();
					return;
				}
				if (currentState.loaded) {
					return;
				}
			}
			update((state) => ({ ...state, loading: true, error: null, searchQuery: '' }));
			try {
				const data = await websitesAPI.list();
				const items = extractWebsiteItems(data);
				setCachedData(CACHE_KEY, items, { ttl: CACHE_TTL, version: CACHE_VERSION });
				update((state) => ({
					...state,
					items,
					loading: false,
					error: null,
					searchQuery: '',
					loaded: true
				}));
			} catch (error) {
				logError('Failed to load websites', error, { scope: 'websitesStore.load' });
				update((state) => ({
					...state,
					loading: false,
					error: 'Failed to load websites',
					searchQuery: '',
					loaded: false
				}));
			}
		},

		async loadById(id: string) {
			update((state) => ({ ...state, loadingDetail: true, error: null }));
			try {
				const data = await websitesAPI.get(id);
				if (!isWebsiteDetail(data)) {
					throw new Error('Invalid website response');
				}
				const summary = buildWebsiteSummary(data);
				update((state) => ({
					...state,
					active: data,
					loadingDetail: false,
					error: null
				}));
				this.upsertFromRealtime(summary);
			} catch (error) {
				logError('Failed to load website', error, {
					scope: 'websitesStore.loadById',
					websiteId: id
				});
				update((state) => ({ ...state, loadingDetail: false, error: 'Failed to load website' }));
			}
		},

		async refreshItem(id: string) {
			try {
				const data = await websitesAPI.get(id);
				if (!isWebsiteDetail(data)) {
					throw new Error('Invalid website response');
				}
				const summary = buildWebsiteSummary(data);
				this.upsertFromRealtime(summary);
				return data;
			} catch (error) {
				logError('Failed to refresh website', error, {
					scope: 'websitesStore.refreshItem',
					websiteId: id
				});
				return null;
			}
		},

		async search(query: string) {
			update((state) => ({ ...state, loading: true, error: null, searchQuery: query }));
			try {
				const data = query ? await websitesAPI.search(query) : await websitesAPI.list();
				const items = extractWebsiteItems(data);
				update((state) => ({
					...state,
					items,
					loading: false,
					error: null,
					searchQuery: query,
					loaded: true
				}));
			} catch (error) {
				logError('Failed to search websites', error, { scope: 'websitesStore.search', query });
				update((state) => ({
					...state,
					loading: false,
					error: 'Failed to search websites',
					searchQuery: query,
					loaded: false
				}));
			}
		},

		clearActive() {
			update((state) => ({ ...state, active: null }));
		},

		async revalidateInBackground() {
			try {
				const data = await websitesAPI.list();
				const freshItems = extractWebsiteItems(data);
				update((state) => {
					const mergedItems = state.items.map((existingItem) => {
						const freshItem = freshItems.find((item) => item.id === existingItem.id);
						if (!freshItem) return existingItem;

						const existingUpdatedAt = existingItem.updated_at || existingItem.saved_at || null;
						const freshUpdatedAt = freshItem.updated_at || freshItem.saved_at || null;

						if (existingUpdatedAt && freshUpdatedAt) {
							const existingTime = new Date(existingUpdatedAt).getTime();
							const freshTime = new Date(freshUpdatedAt).getTime();
							if (
								Number.isFinite(existingTime) &&
								Number.isFinite(freshTime) &&
								existingTime > freshTime
							) {
								return existingItem;
							}
						}

						return { ...existingItem, ...freshItem };
					});

					const newItems = freshItems.filter(
						(freshItem) => !state.items.some((existing) => existing.id === freshItem.id)
					);

					const allItems = [...mergedItems, ...newItems];
					setCachedData(CACHE_KEY, allItems, { ttl: CACHE_TTL, version: CACHE_VERSION });
					return { ...state, items: allItems };
				});
			} catch (error) {
				logError('Background revalidation failed', error, {
					scope: 'websitesStore.revalidateInBackground'
				});
			}
		},

		reset() {
			invalidateCache(CACHE_KEY);
			set({
				items: [],
				loading: false,
				error: null,
				active: null,
				loadingDetail: false,
				searchQuery: '',
				loaded: false
			});
		},

		upsertFromRealtime(item: WebsiteItem) {
			update((state) => {
				const existingIndex = state.items.findIndex((existing) => existing.id === item.id);
				const existing = existingIndex >= 0 ? state.items[existingIndex] : null;
				const incomingUpdatedAt = item.updated_at || item.saved_at || null;
				const existingUpdatedAt = existing?.updated_at || existing?.saved_at || null;
				if (existing && incomingUpdatedAt && existingUpdatedAt) {
					const incomingTime = new Date(incomingUpdatedAt).getTime();
					const existingTime = new Date(existingUpdatedAt).getTime();
					if (
						Number.isFinite(incomingTime) &&
						Number.isFinite(existingTime) &&
						incomingTime < existingTime
					) {
						return state;
					}
				}

				const nextItems = existing
					? state.items.map((existingItem) =>
							existingItem.id === item.id ? { ...existingItem, ...item } : existingItem
						)
					: [item, ...state.items];
				setCachedData(CACHE_KEY, nextItems, { ttl: CACHE_TTL, version: CACHE_VERSION });

				const nextActive =
					state.active && state.active.id === item.id ? { ...state.active, ...item } : state.active;

				return { ...state, items: nextItems, active: nextActive };
			});
		},

		renameLocal(id: string, title: string) {
			update((state) => {
				const items = state.items.map((item) => (item.id === id ? { ...item, title } : item));
				setCachedData(CACHE_KEY, items, { ttl: CACHE_TTL, version: CACHE_VERSION });
				return { ...state, items };
			});
		},

		setPinnedLocal(id: string, pinned: boolean) {
			update((state) => {
				const maxOrder = Math.max(
					-1,
					...state.items
						.filter((item) => item.pinned)
						.map((item) => (typeof item.pinned_order === 'number' ? item.pinned_order : -1))
				);
				const items = state.items.map((item) =>
					item.id === id
						? {
								...item,
								pinned,
								pinned_order: pinned ? (item.pinned_order ?? maxOrder + 1) : null,
								archived: pinned ? false : item.archived,
								updated_at: new Date().toISOString()
							}
						: item
				);
				setCachedData(CACHE_KEY, items, { ttl: CACHE_TTL, version: CACHE_VERSION });
				return { ...state, items };
			});
		},

		setPinnedOrderLocal(order: string[]) {
			update((state) => {
				const orderMap = new Map(order.map((websiteId, index) => [websiteId, index]));
				const items = state.items.map((item) =>
					orderMap.has(item.id) ? { ...item, pinned_order: orderMap.get(item.id) ?? null } : item
				);
				setCachedData(CACHE_KEY, items, { ttl: CACHE_TTL, version: CACHE_VERSION });
				return { ...state, items };
			});
		},

		setArchivedLocal(id: string, archived: boolean) {
			update((state) => {
				const items = state.items.map((item) => (item.id === id ? { ...item, archived } : item));
				setCachedData(CACHE_KEY, items, { ttl: CACHE_TTL, version: CACHE_VERSION });
				return { ...state, items };
			});
		},

		setTranscriptEntryLocal(id: string, videoId: string, entry: WebsiteTranscriptEntry) {
			update((state) => {
				const items = state.items.map((item) =>
					item.id === id
						? {
								...item,
								youtube_transcripts: {
									...(item.youtube_transcripts ?? {}),
									[videoId]: entry
								}
							}
						: item
				);
				setCachedData(CACHE_KEY, items, { ttl: CACHE_TTL, version: CACHE_VERSION });

				const active =
					state.active && state.active.id === id
						? {
								...state.active,
								youtube_transcripts: {
									...(state.active.youtube_transcripts ?? {}),
									[videoId]: entry
								}
							}
						: state.active;

				return { ...state, items, active };
			});
		},

		removeLocal(id: string) {
			update((state) => {
				const items = state.items.filter((item) => item.id !== id);
				setCachedData(CACHE_KEY, items, { ttl: CACHE_TTL, version: CACHE_VERSION });
				return { ...state, items };
			});
		},

		updateActiveLocal(updates: Partial<WebsiteDetail>) {
			update((state) => {
				if (!state.active) return state;
				return {
					...state,
					active: { ...state.active, ...updates }
				};
			});
		}
	};
}

export const websitesStore = createWebsitesStore();
