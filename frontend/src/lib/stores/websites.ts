import { get, writable } from 'svelte/store';
import { websitesAPI } from '$lib/services/api';
import { user } from '$lib/stores/auth';
import {
	enqueueWebsiteSave,
	flushQueuedWebsiteSaves,
	pollUntilComplete
} from '$lib/services/website_save_sync';
import { getCachedData, invalidateCache, setCachedData } from '$lib/utils/cache';
import { logError } from '$lib/utils/errorHandling';

const CACHE_KEY = 'websites.list';
const LAST_SYNC_CACHE_KEY = 'websites.lastSync';
const CACHE_TTL = 15 * 60 * 1000;
const CACHE_VERSION = '1.1';

export interface WebsiteItem {
	id: string;
	title: string;
	url: string;
	domain: string;
	saved_at: string | null;
	created_at?: string | null;
	published_at: string | null;
	pinned: boolean;
	pinned_order?: number | null;
	archived?: boolean;
	favicon_url?: string | null;
	favicon_r2_key?: string | null;
	favicon_extracted_at?: string | null;
	youtube_transcripts?: Record<string, WebsiteTranscriptEntry>;
	reading_time?: string | null;
	updated_at: string | null;
	last_opened_at: string | null;
	deleted_at?: string | null;
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

interface WebsiteAsyncSaveResponse {
	job_id: string;
	status: string;
}

interface SaveWebsiteResult {
	success: boolean;
	queued?: boolean;
	id?: string;
	website?: WebsiteDetail;
	error?: string;
	message?: string;
}

export interface PendingWebsiteItem {
	id: string;
	title: string;
	domain: string;
	url: string;
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
	created_at: data.created_at ?? null,
	published_at: data.published_at,
	pinned: data.pinned ?? false,
	pinned_order: data.pinned_order ?? null,
	archived: data.archived ?? false,
	favicon_url: data.favicon_url ?? null,
	favicon_r2_key: data.favicon_r2_key ?? null,
	favicon_extracted_at: data.favicon_extracted_at ?? null,
	youtube_transcripts: data.youtube_transcripts ?? {},
	reading_time: data.reading_time ?? null,
	updated_at: data.updated_at,
	last_opened_at: data.last_opened_at,
	deleted_at: data.deleted_at ?? null
});

const extractWebsiteItems = (value: unknown): WebsiteItem[] => {
	const data = value as { items?: unknown[] };
	if (Array.isArray(data?.items)) {
		return data.items.filter(isWebsiteItem);
	}
	return [];
};

const isArchivedWebsite = (item: WebsiteItem) => Boolean(item.archived);

const mergeWebsiteCollections = (active: WebsiteItem[], archived: WebsiteItem[]): WebsiteItem[] => {
	const activeIds = new Set(active.map((item) => item.id));
	const filteredArchived = archived.filter((item) => !activeIds.has(item.id));
	return sortWebsiteItems([...active, ...filteredArchived]);
};

const parseAsyncSaveResponse = (value: unknown): WebsiteAsyncSaveResponse | null => {
	if (!value || typeof value !== 'object') return null;
	const payload = value as Record<string, unknown>;
	if (typeof payload.job_id !== 'string' || typeof payload.status !== 'string') return null;
	return { job_id: payload.job_id as string, status: payload.status as string };
};

const getWebsiteSyncTimestamp = (
	item: Pick<WebsiteItem, 'updated_at' | 'saved_at' | 'deleted_at'>
): string | null => item.updated_at ?? item.saved_at ?? item.deleted_at ?? null;

const parseWebsiteTimestamp = (value: string | null | undefined): number | null => {
	if (!value) return null;
	const timestamp = new Date(value).getTime();
	return Number.isFinite(timestamp) ? timestamp : null;
};

const compareNullableDesc = (lhs: number | null, rhs: number | null): number => {
	if (lhs === rhs) return 0;
	if (lhs === null) return 1;
	if (rhs === null) return -1;
	return rhs - lhs;
};

const compareWebsiteItems = (lhs: WebsiteItem, rhs: WebsiteItem): number => {
	const savedComparison = compareNullableDesc(
		parseWebsiteTimestamp(lhs.saved_at),
		parseWebsiteTimestamp(rhs.saved_at)
	);
	if (savedComparison !== 0) return savedComparison;

	const createdComparison = compareNullableDesc(
		parseWebsiteTimestamp(lhs.created_at),
		parseWebsiteTimestamp(rhs.created_at)
	);
	if (createdComparison !== 0) return createdComparison;

	const updatedComparison = compareNullableDesc(
		parseWebsiteTimestamp(lhs.updated_at),
		parseWebsiteTimestamp(rhs.updated_at)
	);
	if (updatedComparison !== 0) return updatedComparison;

	return lhs.id.localeCompare(rhs.id);
};

const sortWebsiteItems = (items: WebsiteItem[]): WebsiteItem[] =>
	[...items].sort(compareWebsiteItems);

const mergeSyncCursor = (current: string | null, candidate: string | null): string | null => {
	if (!current) return candidate;
	if (!candidate) return current;
	const currentTime = new Date(current).getTime();
	const candidateTime = new Date(candidate).getTime();
	if (!Number.isFinite(currentTime)) return candidate;
	if (!Number.isFinite(candidateTime)) return current;
	return candidateTime > currentTime ? candidate : current;
};

const deriveSyncCursor = (items: WebsiteItem[]): string | null =>
	items.reduce<string | null>(
		(cursor, item) => mergeSyncCursor(cursor, getWebsiteSyncTimestamp(item)),
		null
	);

const persistWebsiteCache = (items: WebsiteItem[], lastSync: string | null) => {
	setCachedData(CACHE_KEY, items, { ttl: CACHE_TTL, version: CACHE_VERSION });
	if (lastSync) {
		setCachedData(LAST_SYNC_CACHE_KEY, lastSync, { ttl: CACHE_TTL, version: CACHE_VERSION });
	}
};

const stripWwwPrefix = (value: string): string => value.replace(/^www\./i, '');

const normalizeWebsiteUrl = (url: string): URL | null => {
	const trimmed = url.trim();
	if (!trimmed) return null;
	const withProtocol = /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
	try {
		const parsed = new URL(withProtocol);
		if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
			return null;
		}
		return parsed;
	} catch {
		return null;
	}
};

const buildPendingWebsite = (normalizedUrl: URL): PendingWebsiteItem => {
	const hostname = stripWwwPrefix(normalizedUrl.hostname);
	const display = hostname || normalizedUrl.host || normalizedUrl.href;
	return {
		id:
			typeof globalThis.crypto?.randomUUID === 'function'
				? `pending-${globalThis.crypto.randomUUID()}`
				: `pending-${Date.now()}-${Math.random().toString(16).slice(2)}`,
		title: display,
		domain: display,
		url: normalizedUrl.href
	};
};

const LOCAL_SAVE_RECONCILIATION_WINDOW_MS = 30_000;
const LOCAL_SAVE_RECONCILIATION_LIMIT = 50;
const QUEUED_WEBSITE_MESSAGE = 'Website queued until you sign in again.';

const getErrorStatus = (error: unknown): number | null => {
	if (!error || typeof error !== 'object') return null;
	const status = (error as { status?: unknown }).status;
	return typeof status === 'number' ? status : null;
};

function createWebsitesStore() {
	const freshWebsiteExpirations = new Map<string, number>();

	const pruneFreshWebsiteExpirations = (now: number = Date.now()) => {
		for (const [id, expiresAt] of freshWebsiteExpirations) {
			if (expiresAt <= now) {
				freshWebsiteExpirations.delete(id);
			}
		}
	};

	const noteFreshWebsite = (id: string) => {
		pruneFreshWebsiteExpirations();
		freshWebsiteExpirations.set(id, Date.now() + LOCAL_SAVE_RECONCILIATION_WINDOW_MS);
		if (freshWebsiteExpirations.size <= LOCAL_SAVE_RECONCILIATION_LIMIT) {
			return;
		}
		const sortedEntries = [...freshWebsiteExpirations.entries()].sort(
			(lhs, rhs) => lhs[1] - rhs[1]
		);
		while (sortedEntries.length > LOCAL_SAVE_RECONCILIATION_LIMIT) {
			const oldest = sortedEntries.shift();
			if (!oldest) break;
			freshWebsiteExpirations.delete(oldest[0]);
		}
	};

	const mergeActiveItems = (incoming: WebsiteItem[], current: WebsiteItem[]): WebsiteItem[] => {
		pruneFreshWebsiteExpirations();
		const incomingIds = new Set(incoming.map((item) => item.id));
		for (const id of incomingIds) {
			freshWebsiteExpirations.delete(id);
		}
		const preserved = current.filter(
			(item) =>
				!isArchivedWebsite(item) &&
				freshWebsiteExpirations.has(item.id) &&
				!incomingIds.has(item.id)
		);
		return [...preserved, ...incoming];
	};

	const { subscribe, set, update } = writable<{
		items: WebsiteItem[];
		loading: boolean;
		error: string | null;
		active: WebsiteDetail | null;
		loadingDetail: boolean;
		searchQuery: string;
		loaded: boolean;
		lastSync: string | null;
		archivedLoaded: boolean;
		archivedLoading: boolean;
		isSavingWebsite: boolean;
		pendingWebsite: PendingWebsiteItem | null;
		saveError: string | null;
	}>({
		items: [],
		loading: false,
		error: null,
		active: null,
		loadingDetail: false,
		searchQuery: '',
		loaded: false,
		lastSync: null,
		archivedLoaded: false,
		archivedLoading: false,
		isSavingWebsite: false,
		pendingWebsite: null,
		saveError: null
	});

	return {
		subscribe,

		async load(force: boolean = false) {
			const currentState = get({ subscribe });
			if (!force) {
				const cached = getCachedData<WebsiteItem[]>(CACHE_KEY, {
					ttl: CACHE_TTL,
					version: CACHE_VERSION
				});
				if (cached) {
					const cachedLastSync =
						getCachedData<string>(LAST_SYNC_CACHE_KEY, {
							ttl: CACHE_TTL,
							version: CACHE_VERSION
						}) ?? deriveSyncCursor(cached);
					const cachedActive = cached.filter((item) => !isArchivedWebsite(item));
					const currentArchived = currentState.items.filter((item) => isArchivedWebsite(item));
					const mergedItems = mergeWebsiteCollections(cachedActive, currentArchived);
					persistWebsiteCache(mergedItems, cachedLastSync);
					update((state) => ({
						...state,
						items: mergedItems,
						loading: false,
						error: null,
						searchQuery: '',
						loaded: true,
						lastSync: mergeSyncCursor(state.lastSync, cachedLastSync)
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
				const activeItems = mergeActiveItems(
					extractWebsiteItems(data).filter((item) => !isArchivedWebsite(item)),
					currentState.items.filter((item) => !isArchivedWebsite(item))
				);
				const mergedItems = mergeWebsiteCollections(
					activeItems,
					currentState.items.filter((item) => isArchivedWebsite(item))
				);
				const nextLastSync = mergeSyncCursor(currentState.lastSync, deriveSyncCursor(mergedItems));
				persistWebsiteCache(mergedItems, nextLastSync);
				update((state) => ({
					...state,
					items: mergedItems,
					loading: false,
					error: null,
					searchQuery: '',
					loaded: true,
					lastSync: nextLastSync
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

		async loadArchived(force: boolean = false) {
			const currentState = get({ subscribe });
			if (!force && currentState.archivedLoaded) {
				return;
			}
			update((state) => ({ ...state, archivedLoading: true }));
			try {
				const data = await websitesAPI.listArchived();
				const archivedItems = extractWebsiteItems(data).map((item) => ({
					...item,
					archived: true
				}));
				update((state) => {
					const activeItems = state.items.filter((item) => !isArchivedWebsite(item));
					const mergedItems = mergeWebsiteCollections(activeItems, archivedItems);
					const nextLastSync = mergeSyncCursor(state.lastSync, deriveSyncCursor(mergedItems));
					persistWebsiteCache(mergedItems, nextLastSync);
					return {
						...state,
						items: mergedItems,
						lastSync: nextLastSync,
						archivedLoaded: true,
						archivedLoading: false
					};
				});
			} catch (error) {
				logError('Failed to load archived websites', error, {
					scope: 'websitesStore.loadArchived'
				});
				update((state) => ({ ...state, archivedLoading: false }));
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
				const currentState = get({ subscribe });
				if (currentState.lastSync) {
					const response = await websitesAPI.sync({
						last_sync: currentState.lastSync,
						operations: []
					});
					const syncItems = extractWebsiteItems(response.updates);
					const nextLastSync = mergeSyncCursor(
						currentState.lastSync,
						response.serverUpdatedSince ?? deriveSyncCursor(syncItems)
					);
					update((state) => {
						const existingById = new Map(state.items.map((item) => [item.id, item]));
						for (const syncItem of syncItems) {
							if (syncItem.deleted_at) {
								existingById.delete(syncItem.id);
								continue;
							}
							const existing = existingById.get(syncItem.id);
							existingById.set(syncItem.id, existing ? { ...existing, ...syncItem } : syncItem);
						}
						const orderedExisting = state.items
							.map((item) => existingById.get(item.id))
							.filter((item): item is WebsiteItem => Boolean(item));
						const newItems = syncItems.filter(
							(item) => !item.deleted_at && !state.items.some((existing) => existing.id === item.id)
						);
						const allItems = sortWebsiteItems([...newItems, ...orderedExisting]);
						const nextActive =
							state.active &&
							syncItems.some((item) => item.id === state.active?.id && item.deleted_at)
								? null
								: state.active;
						persistWebsiteCache(allItems, nextLastSync);
						return {
							...state,
							items: allItems,
							active: nextActive,
							lastSync: nextLastSync
						};
					});
					return;
				}

				const data = await websitesAPI.list();
				const freshItems = mergeActiveItems(
					extractWebsiteItems(data).filter((item) => !isArchivedWebsite(item)),
					currentState.items.filter((item) => !isArchivedWebsite(item))
				);
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

					const allItems = sortWebsiteItems([...mergedItems, ...newItems]);
					const nextLastSync = mergeSyncCursor(state.lastSync, deriveSyncCursor(allItems));
					persistWebsiteCache(allItems, nextLastSync);
					return { ...state, items: allItems, lastSync: nextLastSync };
				});
			} catch (error) {
				logError('Background revalidation failed', error, {
					scope: 'websitesStore.revalidateInBackground'
				});
			}
		},

		reset() {
			invalidateCache(CACHE_KEY);
			invalidateCache(LAST_SYNC_CACHE_KEY);
			freshWebsiteExpirations.clear();
			set({
				items: [],
				loading: false,
				error: null,
				active: null,
				loadingDetail: false,
				searchQuery: '',
				loaded: false,
				lastSync: null,
				archivedLoaded: false,
				archivedLoading: false,
				isSavingWebsite: false,
				pendingWebsite: null,
				saveError: null
			});
		},

		clearSaveError() {
			update((state) => ({ ...state, saveError: null }));
		},

		async flushQueuedSaves(): Promise<WebsiteDetail[]> {
			try {
				const queuedWebsites = await flushQueuedWebsiteSaves();
				if (!queuedWebsites.length) {
					return [];
				}

				for (const website of queuedWebsites) {
					noteFreshWebsite(website.id);
					this.upsertFromRealtime(buildWebsiteSummary(website));
				}
				return queuedWebsites;
			} catch (error) {
				logError('Failed to flush queued website saves', error, {
					scope: 'websitesStore.flushQueuedSaves'
				});
				return [];
			}
		},

		async saveWebsite(url: string): Promise<SaveWebsiteResult> {
			const normalized = normalizeWebsiteUrl(url);
			if (!normalized) {
				const error = 'Enter a valid URL.';
				update((state) => ({ ...state, saveError: error }));
				return { success: false, error };
			}

			const pendingWebsite = buildPendingWebsite(normalized);
			update((state) => ({
				...state,
				isSavingWebsite: true,
				pendingWebsite,
				saveError: null
			}));

			const finishQueuedSave = async (): Promise<SaveWebsiteResult> => {
				await enqueueWebsiteSave(normalized.href);
				update((state) => ({
					...state,
					isSavingWebsite: false,
					pendingWebsite: null,
					saveError: null
				}));
				return {
					success: true,
					queued: true,
					message: QUEUED_WEBSITE_MESSAGE
				};
			};

			try {
				if (!get(user)) {
					return finishQueuedSave();
				}

				const result = await websitesAPI.save(normalized.href);
				const asyncResponse = parseAsyncSaveResponse(result);
				if (!asyncResponse) {
					throw new Error('Failed to save website');
				}

				const website = await pollUntilComplete(asyncResponse.job_id);
				if (!website) {
					throw new Error('Failed to save website');
				}
				noteFreshWebsite(website.id);
				this.upsertFromRealtime(buildWebsiteSummary(website));
				if (get({ subscribe }).active?.id === website.id) {
					this.setActiveWebsite(website);
				}

				update((state) => ({
					...state,
					isSavingWebsite: false,
					pendingWebsite: null,
					saveError: null
				}));
				return { success: true, id: website.id, website };
			} catch (error) {
				if (getErrorStatus(error) === 401) {
					return finishQueuedSave();
				}
				const message =
					error instanceof Error && error.message ? error.message : 'Failed to save website';
				update((state) => ({
					...state,
					isSavingWebsite: false,
					pendingWebsite: null,
					saveError: message
				}));
				return { success: false, error: message };
			}
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
				const sortedItems = sortWebsiteItems(nextItems);
				const nextLastSync = mergeSyncCursor(state.lastSync, getWebsiteSyncTimestamp(item));
				persistWebsiteCache(sortedItems, nextLastSync);

				const nextActive =
					state.active && state.active.id === item.id ? { ...state.active, ...item } : state.active;

				return { ...state, items: sortedItems, active: nextActive, lastSync: nextLastSync };
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
		},

		setActiveWebsite(website: WebsiteDetail) {
			update((state) => ({
				...state,
				active: website
			}));
		}
	};
}

export const websitesStore = createWebsitesStore();
