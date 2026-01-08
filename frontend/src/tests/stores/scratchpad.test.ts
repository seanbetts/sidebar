import { describe, it, expect, vi, beforeEach } from 'vitest';
import { scratchpadStore } from '$lib/stores/scratchpad';

const cacheState = new Map<string, string>();

vi.mock('$lib/utils/cache', () => ({
	getCachedData: vi.fn((key: string) => cacheState.get(key) ?? null),
	setCachedData: vi.fn((key: string, value: string) => cacheState.set(key, value))
}));

describe('scratchpadStore', () => {
	beforeEach(() => {
		cacheState.clear();
		vi.clearAllMocks();
	});

	it('returns cached content when available', () => {
		cacheState.set('scratchpad.content', 'hello');
		expect(scratchpadStore.getCachedContent()).toBe('hello');
	});

	it('persists content to cache', () => {
		scratchpadStore.setCachedContent('updated');
		expect(cacheState.get('scratchpad.content')).toBe('updated');
	});
});
