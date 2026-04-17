import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { FileNode, FileTreeState } from '$lib/types/file';
import { createLoadActions } from '$lib/stores/tree/actions/load';
import { createSearchActions } from '$lib/stores/tree/actions/search';
import { createMutationActions } from '$lib/stores/tree/actions/mutations';
import { createResetAction } from '$lib/stores/tree/actions/reset';

const cacheState = new Map<string, unknown>();

const { getCachedData, setCachedData, isCacheStale, invalidateCache } = vi.hoisted(() => ({
	getCachedData: vi.fn((key: string) => cacheState.get(key) ?? null),
	setCachedData: vi.fn((key: string, value: unknown) => cacheState.set(key, value)),
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
		sync: vi.fn(),
		search: vi.fn()
	}
}));

vi.mock('$lib/utils/cache', () => ({
	getCachedData,
	setCachedData,
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
		cacheState.set('tree.notes', [{ name: 'Doc', path: 'doc', type: 'file' }]);
		const { load } = createLoadActions({ update, set, getState });

		await load('notes');

		expect(state.trees.notes?.children).toHaveLength(1);
	});

	it('loads tree from API when cache is missing', async () => {
		notesAPI.listTree.mockResolvedValue({
			children: [{ name: 'File', path: 'file', type: 'file', modified: '2026-04-13T09:00:00Z' }]
		});
		const { load } = createLoadActions({ update, set, getState });

		await load('notes');

		expect(state.trees.notes?.loaded).toBe(true);
		expect(state.trees.notes?.lastSync).toBe('2026-04-13T09:00:00.000Z');
	});

	it('searches notes via API', async () => {
		notesAPI.search.mockResolvedValue([{ name: 'Note', path: 'note', type: 'file' }]);
		const { searchNotes } = createSearchActions({ update, set, getState });

		await searchNotes('query');

		expect(state.trees.notes?.children).toHaveLength(1);
	});

	it('toggles expanded state', () => {
		state = {
			trees: {
				notes: {
					children: [{ name: 'Folder', path: 'folder', type: 'directory', expanded: false }],
					expandedPaths: new Set(),
					loading: false
				}
			}
		};
		const { toggleExpanded } = createMutationActions({ update, set, getState });

		toggleExpanded('notes', 'folder');

		expect(state.trees.notes?.expandedPaths.has('folder')).toBe(true);
	});

	it('resets tree state', () => {
		state = {
			trees: {
				notes: {
					children: [{ name: 'File', path: 'file', type: 'file' }],
					expandedPaths: new Set(),
					loading: false
				}
			}
		};
		const resetTree = createResetAction({ update, set, getState });

		resetTree();

		expect(state.trees.notes).toBeUndefined();
	});

	it('revalidates stale notes tree with sync deltas', async () => {
		cacheState.set('tree.notes', [
			{
				name: 'Cached',
				path: 'note-1',
				type: 'file',
				modified: '2026-04-13T09:00:00Z'
			}
		]);
		cacheState.set('notes.tree.lastSync', '2026-04-13T09:00:00Z');
		isCacheStale.mockReturnValue(true);
		notesAPI.sync.mockResolvedValue({
			applied: [],
			notes: [],
			conflicts: [],
			updates: {
				items: [
					{
						id: 'note-1',
						title: 'Cached Updated',
						folder: '',
						pinned: true,
						pinned_order: 1,
						archived: false,
						updated_at: '2026-04-13T09:05:00Z',
						deleted_at: null
					},
					{
						id: 'note-2',
						title: 'New Note',
						folder: 'Projects',
						pinned: false,
						pinned_order: null,
						archived: false,
						updated_at: '2026-04-13T09:10:00Z',
						deleted_at: null
					}
				]
			},
			serverUpdatedSince: '2026-04-13T09:10:00Z'
		});
		const { load } = createLoadActions({ update, set, getState });

		await load('notes');
		await Promise.resolve();

		expect(notesAPI.listTree).not.toHaveBeenCalled();
		expect(notesAPI.sync).toHaveBeenCalledWith({
			last_sync: '2026-04-13T09:00:00Z',
			operations: [],
			metadata_only: true
		});
		expect(state.trees.notes?.children).toEqual(
			expect.arrayContaining([
				expect.objectContaining({ path: 'note-1', name: 'Cached Updated', pinned: true }),
				expect.objectContaining({ path: 'folder:Projects', type: 'directory' })
			])
		);
		expect(state.trees.notes?.lastSync).toBe('2026-04-13T09:10:00Z');
	});

	it('advances the sync cursor after folder-marker updates force a full reload', async () => {
		cacheState.set('tree.notes', [
			{
				name: 'Cached',
				path: 'note-1',
				type: 'file',
				modified: '2026-04-13T09:00:00Z'
			}
		]);
		cacheState.set('notes.tree.lastSync', '2026-04-13T09:00:00Z');
		isCacheStale.mockReturnValue(true);
		notesAPI.sync.mockResolvedValue({
			applied: [],
			notes: [],
			conflicts: [],
			updates: {
				items: [
					{
						id: 'folder-marker-1',
						title: 'Projects',
						folder: 'Projects',
						pinned: false,
						pinned_order: null,
						archived: false,
						is_folder_marker: true,
						updated_at: '2026-04-13T09:12:00Z',
						deleted_at: null
					}
				]
			},
			serverUpdatedSince: '2026-04-13T09:12:00Z'
		});
		notesAPI.listTree.mockResolvedValue({
			children: [
				{
					name: 'Projects',
					path: 'folder:Projects',
					type: 'directory',
					folderMarker: true,
					children: []
				}
			]
		});
		const { load } = createLoadActions({ update, set, getState });

		await load('notes');
		await Promise.resolve();

		expect(notesAPI.listTree).toHaveBeenCalledTimes(1);
		expect(state.trees.notes?.lastSync).toBe('2026-04-13T09:12:00Z');
	});
});
