import { get } from 'svelte/store';
import { getCachedData, isCacheStale } from '$lib/utils/cache';
import { editorStore } from '$lib/stores/editor';
import type { FileNode } from '$lib/types/file';
import type { TreeStoreContext } from '$lib/stores/tree/types';
import {
	TREE_CACHE_TTL,
	TREE_CACHE_VERSION,
	cacheTree,
	getExpandedCache,
	getTreeCacheKey
} from '$lib/stores/tree/cache';
import { applyExpandedPaths, hasFilePath, sortNodes } from '$lib/stores/tree/nodes';
import { handleFetchError, logError } from '$lib/utils/errorHandling';

export function createLoadActions(context: TreeStoreContext) {
	const ARCHIVE_FOLDER = 'Archive';
	const ARCHIVE_FOLDER_PATH = `folder:${ARCHIVE_FOLDER}`;

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

	const revalidateInBackground = async (basePath: string, expandedPaths: Set<string>) => {
		if (basePath !== 'notes') {
			return;
		}

		try {
			const response = await fetch('/api/v1/notes/tree');
			if (!response.ok) return;
			const data = await response.json();
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
				cacheTree(basePath, finalChildren);

				return {
					trees: {
						...state.trees,
						[basePath]: {
							...(state.trees[basePath] || { expandedPaths }),
							children: finalChildren,
							expandedPaths,
							loading: false,
							error: null,
							loaded: true
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
							loaded: true
						}
					}
				}));
				if (isCacheStale(cacheKey, TREE_CACHE_TTL)) {
					revalidateInBackground(basePath, cachedExpandedPaths);
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
			const response = await fetch('/api/v1/notes/tree');
			if (!response.ok) {
				await handleFetchError(response);
			}

			const data = await response.json();
			const children: FileNode[] = data.children || [];
			context.update((state) => {
				const currentChildren = state.trees[basePath]?.children || [];
				const archivedChildren = archivedChildrenFromNodes(currentChildren);
				const mergedChildren = mergeArchivedNodesIntoTree(children, archivedChildren);
				cacheTree(basePath, mergedChildren);
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
							loaded: true
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
