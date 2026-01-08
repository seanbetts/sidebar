import { beforeEach, describe, expect, it, vi } from 'vitest';
import { get } from 'svelte/store';
import { treeStore } from '$lib/stores/tree';

const cacheState = new Map<string, unknown>();

vi.mock('$lib/utils/cache', () => ({
	getCachedData: vi.fn((key: string) => cacheState.get(key) ?? null),
	setCachedData: vi.fn((key: string, value: unknown) => cacheState.set(key, value)),
	isCacheStale: vi.fn(() => false),
	invalidateCache: vi.fn()
}));

describe('treeStore', () => {
	beforeEach(() => {
		cacheState.clear();
		vi.clearAllMocks();
	});

	it('adds a note node to the notes tree', () => {
		treeStore.addNoteNode({
			id: 'note-1',
			name: 'Welcome Note',
			folder: 'Work',
			pinned: false
		});

		const state = get(treeStore);
		const notesTree = state.trees.notes;
		expect(notesTree).toBeTruthy();
		expect(notesTree?.children?.length).toBeGreaterThan(0);

		const folder = notesTree?.children?.find((node) => node.type === 'directory');
		expect(folder?.path).toBe('folder:Work');
		expect(folder?.children?.some((node) => node.path === 'note-1')).toBe(true);
	});
});
