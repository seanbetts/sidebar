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
import { applyExpandedPaths, hasFilePath } from '$lib/stores/tree/nodes';

export function createLoadActions(context: TreeStoreContext) {
  const revalidateInBackground = async (basePath: string, expandedPaths: Set<string>) => {
    try {
      const endpoint = basePath === 'notes'
        ? '/api/v1/notes/tree'
        : `/api/v1/files?basePath=${basePath}`;
      const response = await fetch(endpoint);
      if (!response.ok) return;
      const data = await response.json();
      const children: FileNode[] = data.children || [];
      cacheTree(basePath, children);
      context.update((state) => ({
        trees: {
          ...state.trees,
          [basePath]: {
            ...(state.trees[basePath] || { expandedPaths }),
            children: applyExpandedPaths(children, expandedPaths),
            expandedPaths,
            loading: false,
            error: null,
            loaded: true
          }
        }
      }));
    } catch (error) {
      console.error(`Background revalidation failed for ${basePath}:`, error);
    }
  };

  const load = async (basePath: string = 'documents', force: boolean = false) => {
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
          error: null,
          searchQuery: '',
          loaded: state.trees[basePath]?.loaded ?? false
        }
      }
    }));

    try {
      const endpoint = basePath === 'notes'
        ? '/api/v1/notes/tree'
        : `/api/v1/files?basePath=${basePath}`;
      const response = await fetch(endpoint);
      if (!response.ok) throw new Error('Failed to load files');

      const data = await response.json();
      const children: FileNode[] = data.children || [];
      cacheTree(basePath, children);
      context.update((state) => ({
        trees: {
          ...state.trees,
          [basePath]: {
            ...state.trees[basePath],
            children: applyExpandedPaths(children, cachedExpandedPaths),
            expandedPaths: cachedExpandedPaths,
            loading: false,
            error: null,
            searchQuery: '',
            loaded: true
          }
        }
      }));

      if (basePath === 'notes') {
        const editorState = get(editorStore);
        if (editorState.currentNoteId && !hasFilePath(children, editorState.currentNoteId)) {
          editorStore.reset();
        }
      }
    } catch (error) {
      console.error(`Failed to load file tree for ${basePath}:`, error);
      context.update((state) => ({
        trees: {
          ...state.trees,
          [basePath]: {
            ...state.trees[basePath],
            loading: false,
            error: 'Service unavailable',
            searchQuery: '',
            loaded: false
          }
        }
      }));
    }
  };

  return { load, revalidateInBackground };
}
