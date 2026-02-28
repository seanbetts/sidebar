import { beforeEach, describe, expect, it, vi } from 'vitest';

const clearTaskCacheStorage = vi.fn(async () => undefined);

vi.mock('$lib/stores/task_cache', () => ({
	clearTaskCacheStorage
}));

describe('sessionCleanup', () => {
	beforeEach(() => {
		clearTaskCacheStorage.mockClear();
		localStorage.clear();
		sessionStorage.clear();
	});

	it('flushClientSessionOnLogout removes session-prefixed storage and cache across users', async () => {
		const { flushClientSessionOnLogout } = await import('$lib/utils/sessionCleanup');

		localStorage.setItem('sideBar.cache.user-a.tasks', '{"value":"a"}');
		localStorage.setItem('sideBar.cache.user-b.tasks', '{"value":"b"}');
		localStorage.setItem('sideBar.layout', '{"leftPanel":true}');
		localStorage.setItem('sidebar.weatherUsesFahrenheit', 'true');
		localStorage.setItem('sb-example-auth-token', '{"access_token":"secret"}');
		localStorage.setItem('supabase.auth.token', '{"access_token":"legacy-secret"}');
		localStorage.setItem('theme', 'dark');
		sessionStorage.setItem('sideBar.tempToken', 'abc');
		sessionStorage.setItem('sb-example-auth-token', '{"access_token":"secret"}');
		sessionStorage.setItem('other.tempToken', 'def');

		await flushClientSessionOnLogout();

		expect(localStorage.getItem('sideBar.cache.user-a.tasks')).toBeNull();
		expect(localStorage.getItem('sideBar.cache.user-b.tasks')).toBeNull();
		expect(localStorage.getItem('sideBar.layout')).toBeNull();
		expect(localStorage.getItem('sidebar.weatherUsesFahrenheit')).toBeNull();
		expect(localStorage.getItem('sb-example-auth-token')).toBeNull();
		expect(localStorage.getItem('supabase.auth.token')).toBeNull();
		expect(localStorage.getItem('theme')).toBe('dark');
		expect(sessionStorage.getItem('sideBar.tempToken')).toBeNull();
		expect(sessionStorage.getItem('sb-example-auth-token')).toBeNull();
		expect(sessionStorage.getItem('other.tempToken')).toBe('def');
		expect(clearTaskCacheStorage).toHaveBeenCalledTimes(1);
	});

	it('clearClientCaches removes cache data without removing non-cache preferences', async () => {
		const { clearClientCaches } = await import('$lib/utils/sessionCleanup');

		localStorage.setItem('sideBar.cache.user-a.tasks', '{"value":"a"}');
		localStorage.setItem('sideBar.layout', '{"leftPanel":true}');

		await clearClientCaches();

		expect(localStorage.getItem('sideBar.cache.user-a.tasks')).toBeNull();
		expect(localStorage.getItem('sideBar.layout')).toBe('{"leftPanel":true}');
		expect(clearTaskCacheStorage).toHaveBeenCalledTimes(1);
	});
});
