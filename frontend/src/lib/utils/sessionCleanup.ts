import { clearTaskCacheStorage } from '$lib/stores/task_cache';
import { clearCachesForAllUsers, clearInFlight, clearMemoryCache } from '$lib/utils/cache';

const SESSION_STORAGE_PREFIXES = ['sideBar.', 'sidebar.', 'sb-', 'supabase.auth.'];

function clearPrefixedStorage(storage: Storage, prefixes: string[]): void {
	const keys = Object.keys(storage);
	keys.forEach((key) => {
		if (prefixes.some((prefix) => key.startsWith(prefix))) {
			storage.removeItem(key);
		}
	});
}

/**
 * Flush client session data during logout.
 */
export async function flushClientSessionOnLogout(): Promise<void> {
	clearInFlight();
	clearMemoryCache();
	clearCachesForAllUsers();
	if (typeof localStorage !== 'undefined') {
		clearPrefixedStorage(localStorage, SESSION_STORAGE_PREFIXES);
	}
	if (typeof sessionStorage !== 'undefined') {
		clearPrefixedStorage(sessionStorage, SESSION_STORAGE_PREFIXES);
	}
	await clearTaskCacheStorage();
}

/**
 * Flush cached client data while keeping non-cache preferences untouched.
 */
export async function clearClientCaches(): Promise<void> {
	clearInFlight();
	clearMemoryCache();
	clearCachesForAllUsers();
	await clearTaskCacheStorage();
}
