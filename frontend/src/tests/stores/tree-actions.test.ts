import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { FileNode, FileTreeState } from '$lib/types/file';
import { createLoadActions } from '$lib/stores/tree/actions/load';
import { createSearchActions } from '$lib/stores/tree/actions/search';
import { createMutationActions } from '$lib/stores/tree/actions/mutations';
import { createResetAction } from '$lib/stores/tree/actions/reset';

const cacheState = new Map<string, FileNode[]>();

const { getCachedData, isCacheStale, invalidateCache } = vi.hoisted(() => ({
	getCachedData: vi.fn((key: string) => cacheState.get(key) ?? null),
	isCacheStale: vi.fn(() => false),
	invalidateCache: vi.fn()
}));

const { cacheTree, cacheExpanded, getExpandedCache } = vi.hoisted(() => ({
	cacheTree: vi.fn(),
	cacheExpanded: vi.fn(),
	getExpandedCache: vi.fn(() => [])
}));

const { notesAPI } = vi.hoisted(() => ({
	notesAPI: {
		listTree: vi.fn(),
		search: vi.fn()
	}
}));

vi.mock('$lib/utils/cache', () => ({
	getCachedData,
	isCacheStale,
	invalidateCache
}));

vi.mock('$lib/stores/tree/cache', () => ({
	TREE_CACHE_TTL: 1,
	TREE_CACHE_VERSION: '1',
	cacheTree,
	cacheExpanded,
	getExpandedCache,
	getTreeCacheKey: (basePath: string) => `tree.${basePath}`,
	getExpandedCacheKey: (basePath: string) => `tree.expanded.${basePath}`
}));

vi.mock('$lib/services/api', () => ({ notesAPI }));

describe('tree actions', () => {
	let state: FileTreeState;
	const update = (fn: (s: FileTreeState) => FileTreeState) => {
		state = fn(state);
	};
	const set = (next: FileTreeState) => {
		state = next;
	};
	const getState = () => state;

	beforeEach(() => {
		state = { trees: {} };
		cacheState.clear();
		vi.clearAllMocks();
	});

	it('loads tree from cache when available', async () => {
		cacheState.set('tree.documents', [{ name: 'Doc', path: 'doc', type: 'file' }]);
		const { load } = createLoadActions({ update, set, getState });

		await load('documents');

		expect(state.trees.documents?.children).toHaveLength(1);
	});

	it('loads tree from API when cache is missing', async () => {
		vi.spyOn(global, 'fetch').mockResolvedValue({
			ok: true,
			json: async () => ({ children: [{ name: 'File', path: 'file', type: 'file' }] })
		} as Response);
		const { load } = createLoadActions({ update, set, getState });

		await load('documents');

		expect(state.trees.documents?.loaded).toBe(true);
	});

	it('searches notes via API', async () => {
		notesAPI.search.mockResolvedValue([{ name: 'Note', path: 'note', type: 'file' }]);
		const { searchNotes } = createSearchActions({ update, set, getState });

		await searchNotes('query');

		expect(state.trees.notes?.children).toHaveLength(1);
	});

	it('searches files via fetch', async () => {
		vi.spyOn(global, 'fetch').mockResolvedValue({
			ok: true,
			json: async () => ({ items: [{ name: 'File', path: 'file', type: 'file' }] })
		} as Response);
		const { searchFiles } = createSearchActions({ update, set, getState });

		await searchFiles('documents', 'q');

		expect(state.trees.documents?.children).toHaveLength(1);
	});

	it('toggles expanded state', () => {
		state = {
			trees: {
				documents: {
					children: [{ name: 'Folder', path: 'folder', type: 'directory', expanded: false }],
					expandedPaths: new Set(),
					loading: false
				}
			}
		};
		const { toggleExpanded } = createMutationActions({ update, set, getState });

		toggleExpanded('documents', 'folder');

		expect(state.trees.documents?.expandedPaths.has('folder')).toBe(true);
	});

	it('resets tree state', () => {
		state = {
			trees: {
				documents: {
					children: [{ name: 'File', path: 'file', type: 'file' }],
					expandedPaths: new Set(),
					loading: false
				}
			}
		};
		const resetTree = createResetAction({ update, set, getState });

		resetTree();

		expect(state.trees.documents).toBeUndefined();
	});
});
