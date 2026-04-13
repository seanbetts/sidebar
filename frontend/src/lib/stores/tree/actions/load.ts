import { get } from 'svelte/store';
import { getCachedData, isCacheStale, setCachedData } from '$lib/utils/cache';
import { editorStore } from '$lib/stores/editor';
import { notesAPI } from '$lib/services/api';
import type { FileNode } from '$lib/types/file';
import type { TreeStoreContext } from '$lib/stores/tree/types';
import {
	TREE_CACHE_TTL,
	TREE_CACHE_VERSION,
	cacheTree,
	getExpandedCache,
	getTreeCacheKey
} from '$lib/stores/tree/cache';
import {
	applyExpandedPaths,
	hasFilePath,
	insertNoteIntoFolder,
	removeNodeFromTree,
	sortNodes
} from '$lib/stores/tree/nodes';
import { handleFetchError, logError } from '$lib/utils/errorHandling';

export function createLoadActions(context: TreeStoreContext) {
	const ARCHIVE_FOLDER = 'Archive';
	const ARCHIVE_FOLDER_PATH = `folder:${ARCHIVE_FOLDER}`;
	const LAST_SYNC_CACHE_KEY = 'notes.tree.lastSync';

	type NoteSyncItem = {
		id: string;
		title: string;
		folder: string;
		pinned: boolean;
		pinned_order?: number | null;
		archived: boolean;
		is_folder_marker?: boolean;
		updated_at?: string | null;
		deleted_at?: string | null;
	};

	const mergeSyncCursor = (current: string | null, candidate: string | null): string | null => {
		if (!current) return candidate;
		if (!candidate) return current;
		const currentTime = new Date(current).getTime();
		const candidateTime = new Date(candidate).getTime();
		if (!Number.isFinite(currentTime)) return candidate;
		if (!Number.isFinite(candidateTime)) return current;
		return candidateTime > currentTime ? candidate : current;
	};

	const normalizeNodeTimestamp = (value: unknown): string | null => {
		if (typeof value !== 'string' && typeof value !== 'number') {
			return null;
		}
		const timestamp = new Date(value).getTime();
		if (!Number.isFinite(timestamp)) {
			return null;
		}
		return new Date(timestamp).toISOString();
	};

	const deriveSyncCursorFromTree = (nodes: FileNode[]): string | null => {
		let cursor: string | null = null;
		const visit = (items: FileNode[]) => {
			for (const item of items) {
				if (item.type === 'file') {
					cursor = mergeSyncCursor(cursor, normalizeNodeTimestamp(item.modified));
				}
				if (item.children) {
					visit(item.children);
				}
			}
		};
		visit(nodes);
		return cursor;
	};

	const getCachedLastSync = (): string | null =>
		getCachedData<string>(LAST_SYNC_CACHE_KEY, {
			ttl: TREE_CACHE_TTL,
			version: TREE_CACHE_VERSION
		});

	const setCachedLastSync = (lastSync: string | null) => {
		if (!lastSync) return;
		setCachedData(LAST_SYNC_CACHE_KEY, lastSync, {
			ttl: TREE_CACHE_TTL,
			version: TREE_CACHE_VERSION
		});
	};

	const isNoteSyncItem = (value: unknown): value is NoteSyncItem => {
		if (!value || typeof value !== 'object') return false;
		const item = value as Record<string, unknown>;
		return (
			typeof item.id === 'string' &&
			typeof item.title === 'string' &&
			typeof item.folder === 'string'
		);
	};

	const extractSyncItems = (value: unknown): NoteSyncItem[] => {
		const items = (value as { items?: unknown[] } | null)?.items;
		return Array.isArray(items) ? items.filter(isNoteSyncItem) : [];
	};

	const toFileNode = (item: NoteSyncItem): FileNode => ({
		name: item.title,
		path: item.id,
		type: 'file',
		modified: item.updated_at ?? undefined,
		pinned: item.pinned,
		pinned_order: item.pinned_order ?? null,
		archived: item.archived
	});

	const isArchiveDirectory = (node: FileNode): boolean =>
		node.type === 'directory' && node.path === ARCHIVE_FOLDER_PATH;

	const normalizeArchivedNodes = (nodes: FileNode[]): FileNode[] =>
		nodes.flatMap((node) => {
			if (isArchiveDirectory(node)) {
				return node.children || [];
			}
			return [node];
		});

	const markArchivedNodes = (nodes: FileNode[]): FileNode[] =>
		nodes.map((node) => {
			if (node.type === 'file') {
				return { ...node, archived: true };
			}
			if (node.children) {
				return {
					...node,
					children: markArchivedNodes(node.children)
				};
			}
			return node;
		});

	const archivedChildrenFromNodes = (nodes: FileNode[]): FileNode[] => {
		const archiveNode = nodes.find((node) => isArchiveDirectory(node));
		return archiveNode?.children || [];
	};

	const mergeArchivedNodesIntoTree = (
		activeNodes: FileNode[],
		archivedNodes: FileNode[]
	): FileNode[] => {
		const existingArchive = activeNodes.find((node) => isArchiveDirectory(node));
		const nonArchiveNodes = activeNodes.filter((node) => !isArchiveDirectory(node));
		const normalizedArchivedNodes = normalizeArchivedNodes(archivedNodes);
		const archiveChildren = markArchivedNodes(normalizedArchivedNodes);
		if (archiveChildren.length === 0) {
			return nonArchiveNodes;
		}
		const archiveNode: FileNode = {
			name: ARCHIVE_FOLDER,
			path: ARCHIVE_FOLDER_PATH,
			type: 'directory',
			children: archiveChildren,
			expanded: existingArchive?.expanded,
			folderMarker: existingArchive?.folderMarker
		};
		return sortNodes([...nonArchiveNodes, archiveNode]);
	};

	const mergeFileNodes = (existingNodes: FileNode[], freshNodes: FileNode[]): FileNode[] => {
		const result: FileNode[] = [];
		const freshMap = new Map(freshNodes.map((node) => [node.path, node]));
		const processedPaths = new Set<string>();

		// Merge existing nodes with fresh data
		for (const existingNode of existingNodes) {
			const freshNode = freshMap.get(existingNode.path);
			processedPaths.add(existingNode.path);

			if (!freshNode) {
				// Node was removed on server
				continue;
			}

			if (existingNode.type === 'directory' && freshNode.type === 'directory') {
				// Recursively merge directory children
				const mergedChildren =
					existingNode.children && freshNode.children
						? mergeFileNodes(existingNode.children, freshNode.children)
						: freshNode.children || existingNode.children || [];
				result.push({ ...freshNode, children: mergedChildren, expanded: existingNode.expanded });
			} else if (existingNode.type === 'file' && freshNode.type === 'file') {
				// Check timestamps for files
				const existingModified = existingNode.modified;
				const freshModified = freshNode.modified;

				if (existingModified && freshModified) {
					const existingTime = new Date(existingModified).getTime();
					const freshTime = new Date(freshModified).getTime();
					if (
						Number.isFinite(existingTime) &&
						Number.isFinite(freshTime) &&
						existingTime > freshTime
					) {
						// Keep existing node if it's newer
						result.push(existingNode);
						continue;
					}
				}

				// Use fresh data
				result.push(freshNode);
			} else {
				// Type mismatch, use fresh
				result.push(freshNode);
			}
		}

		// Add new nodes from fresh data
		for (const freshNode of freshNodes) {
			if (!processedPaths.has(freshNode.path)) {
				result.push(freshNode);
			}
		}

		return result;
	};

	const applyNoteDeltaUpdates = (
		children: FileNode[],
		syncItems: NoteSyncItem[],
		includeArchived: boolean
	): { children: FileNode[]; requiresFullReload: boolean } => {
		let nextChildren = children;
		for (const item of syncItems) {
			if (item.is_folder_marker) {
				return { children, requiresFullReload: true };
			}
			nextChildren = removeNodeFromTree(nextChildren, item.id).nodes;
			if (item.deleted_at || (item.archived && !includeArchived)) {
				continue;
			}
			const targetFolder = item.archived ? ARCHIVE_FOLDER : item.folder;
			nextChildren = insertNoteIntoFolder(nextChildren, toFileNode(item), targetFolder);
		}
		return { children: nextChildren, requiresFullReload: false };
	};

	const revalidateInBackground = async (
		basePath: string,
		expandedPaths: Set<string>,
		lastSync: string | null = null
	) => {
		if (basePath !== 'notes') {
			return;
		}

		try {
			if (lastSync) {
				const response = await notesAPI.sync({
					last_sync: lastSync,
					operations: []
				});
				const syncItems = extractSyncItems(response.updates);
				let shouldReloadFully = false;

				context.update((state) => {
					const existingTree = state.trees[basePath];
					const includeArchived =
						Boolean(existingTree?.archivedLoaded) ||
						Boolean(existingTree?.children?.some((node) => isArchiveDirectory(node)));
					const deltaResult = applyNoteDeltaUpdates(
						existingTree?.children || [],
						syncItems,
						includeArchived
					);
					if (deltaResult.requiresFullReload) {
						shouldReloadFully = true;
						return state;
					}

					const finalChildren = applyExpandedPaths(deltaResult.children, expandedPaths);
					const nextLastSync = mergeSyncCursor(lastSync, response.serverUpdatedSince ?? null);
					cacheTree(basePath, finalChildren);
					setCachedLastSync(nextLastSync);

					return {
						trees: {
							...state.trees,
							[basePath]: {
								...(state.trees[basePath] || { expandedPaths }),
								children: finalChildren,
								expandedPaths,
								loading: false,
								archivedLoading: state.trees[basePath]?.archivedLoading ?? false,
								archivedLoaded: state.trees[basePath]?.archivedLoaded ?? false,
								error: null,
								loaded: true,
								lastSync: nextLastSync
							}
						}
					};
				});

				if (!shouldReloadFully) {
					return;
				}
			}

			const data = await notesAPI.listTree();
			const freshChildren: FileNode[] = data.children || [];

			context.update((state) => {
				const existingTree = state.trees[basePath];
				const existingChildren = existingTree?.children || [];
				const archivedChildren = archivedChildrenFromNodes(existingChildren);

				// Merge trees intelligently with timestamp checking
				const mergedActiveChildren =
					existingChildren.length > 0
						? mergeFileNodes(existingChildren, freshChildren)
						: freshChildren;
				const mergedChildren = mergeArchivedNodesIntoTree(mergedActiveChildren, archivedChildren);

				const finalChildren = applyExpandedPaths(mergedChildren, expandedPaths);
				const nextLastSync = deriveSyncCursorFromTree(finalChildren);
				cacheTree(basePath, finalChildren);
				setCachedLastSync(nextLastSync);

				return {
					trees: {
						...state.trees,
						[basePath]: {
							...(state.trees[basePath] || { expandedPaths }),
							children: finalChildren,
							expandedPaths,
							loading: false,
							error: null,
							loaded: true,
							lastSync: nextLastSync
						}
					}
				};
			});
		} catch (error) {
			logError('Background revalidation failed', error, { basePath });
		}
	};

	const load = async (basePath: string = 'notes', force: boolean = false) => {
		if (basePath !== 'notes') {
			logError('Unsupported tree base path', new Error('Unsupported tree base path'), {
				basePath
			});
			return;
		}

		const currentState = context.getState();
		const currentTree = currentState.trees[basePath];
		const expandedCache = getExpandedCache(basePath);
		const cachedExpandedPaths = new Set(expandedCache || []);

		if (currentTree?.loading) {
			return;
		}

		if (!force) {
			const cacheKey = getTreeCacheKey(basePath);
			const cached = getCachedData<FileNode[]>(cacheKey, {
				ttl: TREE_CACHE_TTL,
				version: TREE_CACHE_VERSION
			});
			if (cached) {
				const cachedLastSync = getCachedLastSync() ?? deriveSyncCursorFromTree(cached);
				setCachedLastSync(cachedLastSync);
				context.update((state) => ({
					trees: {
						...state.trees,
						[basePath]: {
							...(state.trees[basePath] || { children: [], expandedPaths: cachedExpandedPaths }),
							children: applyExpandedPaths(cached, cachedExpandedPaths),
							expandedPaths: cachedExpandedPaths,
							loading: false,
							archivedLoading: state.trees[basePath]?.archivedLoading ?? false,
							archivedLoaded: state.trees[basePath]?.archivedLoaded ?? false,
							error: null,
							searchQuery: '',
							loaded: true,
							lastSync: mergeSyncCursor(state.trees[basePath]?.lastSync ?? null, cachedLastSync)
						}
					}
				}));
				if (isCacheStale(cacheKey, TREE_CACHE_TTL)) {
					revalidateInBackground(basePath, cachedExpandedPaths, cachedLastSync);
				}
				return;
			}

			if (currentTree?.children && currentTree.children.length > 0) {
				return;
			}

			if (currentTree?.loaded) {
				return;
			}
		}

		context.update((state) => ({
			trees: {
				...state.trees,
				[basePath]: {
					...(state.trees[basePath] || { children: [], expandedPaths: cachedExpandedPaths }),
					loading: true,
					archivedLoading: state.trees[basePath]?.archivedLoading ?? false,
					archivedLoaded: state.trees[basePath]?.archivedLoaded ?? false,
					error: null,
					searchQuery: '',
					loaded: state.trees[basePath]?.loaded ?? false
				}
			}
		}));

		try {
			const data = await notesAPI.listTree();
			const children: FileNode[] = data.children || [];
			context.update((state) => {
				const currentChildren = state.trees[basePath]?.children || [];
				const archivedChildren = archivedChildrenFromNodes(currentChildren);
				const mergedChildren = mergeArchivedNodesIntoTree(children, archivedChildren);
				const nextLastSync = deriveSyncCursorFromTree(mergedChildren);
				cacheTree(basePath, mergedChildren);
				setCachedLastSync(nextLastSync);
				return {
					trees: {
						...state.trees,
						[basePath]: {
							...state.trees[basePath],
							children: applyExpandedPaths(mergedChildren, cachedExpandedPaths),
							expandedPaths: cachedExpandedPaths,
							loading: false,
							archivedLoading: state.trees[basePath]?.archivedLoading ?? false,
							archivedLoaded: state.trees[basePath]?.archivedLoaded ?? false,
							error: null,
							searchQuery: '',
							loaded: true,
							lastSync: nextLastSync
						}
					}
				};
			});

			if (basePath === 'notes') {
				const editorState = get(editorStore);
				if (editorState.currentNoteId && !hasFilePath(children, editorState.currentNoteId)) {
					editorStore.reset();
				}
			}
		} catch (error) {
			logError('Failed to load file tree', error, { basePath });
			context.update((state) => ({
				trees: {
					...state.trees,
					[basePath]: {
						...state.trees[basePath],
						loading: false,
						archivedLoading: state.trees[basePath]?.archivedLoading ?? false,
						archivedLoaded: state.trees[basePath]?.archivedLoaded ?? false,
						error: 'Service unavailable',
						searchQuery: '',
						loaded: false
					}
				}
			}));
		}
	};

	const loadArchived = async (basePath: string = 'notes', force: boolean = false) => {
		if (basePath !== 'notes') {
			return;
		}

		const currentTree = context.getState().trees[basePath];
		if (currentTree?.archivedLoading) {
			return;
		}
		if (
			!force &&
			currentTree?.archivedLoaded &&
			currentTree.children?.some((node) => isArchiveDirectory(node))
		) {
			return;
		}

		context.update((state) => {
			const tree = state.trees[basePath] || {
				children: [],
				expandedPaths: new Set<string>(),
				loading: false
			};
			return {
				trees: {
					...state.trees,
					[basePath]: {
						...tree,
						archivedLoading: true,
						archivedLoaded: tree.archivedLoaded ?? false
					}
				}
			};
		});

		try {
			const response = await fetch('/api/v1/notes/archived?limit=500&offset=0');
			if (!response.ok) {
				await handleFetchError(response);
			}

			const data = await response.json();
			const archivedChildren: FileNode[] = Array.isArray(data?.children)
				? (data.children as FileNode[])
				: [];

			context.update((state) => {
				const tree = state.trees[basePath] || {
					children: [],
					expandedPaths: new Set<string>(),
					loading: false
				};
				const expandedPaths = tree.expandedPaths || new Set<string>();
				const mergedChildren = mergeArchivedNodesIntoTree(tree.children || [], archivedChildren);
				cacheTree(basePath, mergedChildren);
				return {
					trees: {
						...state.trees,
						[basePath]: {
							...tree,
							children: applyExpandedPaths(mergedChildren, expandedPaths),
							expandedPaths,
							archivedLoading: false,
							archivedLoaded: true,
							error: null,
							loaded: true
						}
					}
				};
			});
		} catch (error) {
			logError('Failed to load archived notes', error, { basePath });
			context.update((state) => {
				const tree = state.trees[basePath];
				if (!tree) return state;
				return {
					trees: {
						...state.trees,
						[basePath]: {
							...tree,
							archivedLoading: false
						}
					}
				};
			});
		}
	};

	return { load, revalidateInBackground, loadArchived };
}
