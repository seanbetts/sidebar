import type { TaskCacheSnapshot } from '$lib/stores/task_cache';
import type { TaskCountsResponse } from '$lib/types/tasks';

type CacheOptions = { ttl: number; version: string };
type CacheWriter = (key: string, value: unknown, options: CacheOptions) => void;

/**
 * Memoize task cache snapshots and de-duplicate concurrent loads.
 */
export const createSnapshotLoader = (loadSnapshot: () => Promise<TaskCacheSnapshot>) => {
	let snapshotPromise: Promise<TaskCacheSnapshot> | null = null;
	let snapshotCache: TaskCacheSnapshot | null = null;

	const reset = () => {
		snapshotCache = null;
		snapshotPromise = null;
	};

	const load = async () => {
		if (snapshotCache) return snapshotCache;
		if (!snapshotPromise) {
			snapshotPromise = loadSnapshot();
		}
		snapshotCache = await snapshotPromise;
		return snapshotCache;
	};

	return { load, reset };
};

/**
 * Apply counts state and update the cached counts payload.
 */
export const createCountsApplier = <
	TState extends { counts: Record<string, number>; todayCount: number }
>(
	update: (updater: (state: TState) => TState) => void,
	setCachedData: CacheWriter,
	cacheKey: string,
	cacheOptions: CacheOptions,
	buildCountsMap: (counts: TaskCountsResponse) => Record<string, number>
) => {
	return (counts: TaskCountsResponse) => {
		const map = buildCountsMap(counts);
		update((state) => ({
			...state,
			counts: map,
			todayCount: counts.counts.today
		}));
		setCachedData(cacheKey, counts, cacheOptions);
	};
};
