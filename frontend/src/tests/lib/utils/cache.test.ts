import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
	clearCaches,
	clearCachesForAllUsers,
	clearInFlight,
	clearMemoryCache,
	getCachedData,
	loadData,
	setCachedData
} from '$lib/utils/cache';

describe('cache freshness', () => {
	beforeEach(() => {
		vi.useFakeTimers();
		clearInFlight();
		clearMemoryCache();
		clearCaches();
	});

	afterEach(() => {
		vi.useRealTimers();
		clearInFlight();
		clearMemoryCache();
		clearCaches();
	});

	it('does not return expired in-memory entries', () => {
		vi.setSystemTime(new Date('2026-01-01T00:00:00.000Z'));
		setCachedData('weather.snapshot', { temp: 20 }, { ttl: 1_000, version: '1.0' });

		expect(
			getCachedData<{ temp: number }>('weather.snapshot', { ttl: 1_000, version: '1.0' })
		).toEqual({
			temp: 20
		});

		vi.advanceTimersByTime(1_500);
		expect(
			getCachedData<{ temp: number }>('weather.snapshot', { ttl: 1_000, version: '1.0' })
		).toBeNull();
	});

	it('loadData fetches fresh value when memory cache entry is stale', async () => {
		vi.setSystemTime(new Date('2026-01-01T00:00:00.000Z'));
		setCachedData('location.live', 'Old Value', { ttl: 1_000, version: '1.0' });
		vi.advanceTimersByTime(1_500);

		const fetcher = vi.fn().mockResolvedValue('Fresh Value');
		const result = await loadData('location.live', fetcher, { ttl: 1_000, version: '1.0' });

		expect(result).toBe('Fresh Value');
		expect(fetcher).toHaveBeenCalledTimes(1);
	});

	it('clearCachesForAllUsers removes cache entries across user prefixes', () => {
		localStorage.setItem('sideBar.cache.user-a.tasks.list', '{"v":1}');
		localStorage.setItem('sideBar.cache.user-b.tasks.list', '{"v":2}');
		localStorage.setItem('sideBar.layout', '{"sidebar":"expanded"}');

		clearCachesForAllUsers();

		expect(localStorage.getItem('sideBar.cache.user-a.tasks.list')).toBeNull();
		expect(localStorage.getItem('sideBar.cache.user-b.tasks.list')).toBeNull();
		expect(localStorage.getItem('sideBar.layout')).toBe('{"sidebar":"expanded"}');
	});
});
