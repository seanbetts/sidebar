import type { FileNode } from '$lib/types/file';
import type { TreeStoreContext } from '$lib/stores/tree/types';
import { notesAPI } from '$lib/services/api';
import { handleFetchError, logError } from '$lib/utils/errorHandling';

export function createSearchActions(context: TreeStoreContext) {
  const isFileNode = (value: unknown): value is FileNode => {
    if (!value || typeof value !== 'object') return false;
    const node = value as Record<string, unknown>;
    return typeof node.name === 'string' && typeof node.path === 'string' && typeof node.type === 'string';
  };

  const searchNotes = async (query: string) => {
    context.update((state) => ({
      trees: {
        ...state.trees,
        notes: {
          ...(state.trees.notes || { children: [], expandedPaths: new Set() }),
          loading: true,
          searchQuery: query
        }
      }
    }));

    try {
      const children = query
        ? await notesAPI.search(query)
        : (await notesAPI.listTree()).children;
      context.update((state) => ({
        trees: {
          ...state.trees,
          notes: {
            ...(state.trees.notes || { children: [], expandedPaths: new Set() }),
            children,
            loading: false,
            searchQuery: query,
            loaded: true
          }
        }
      }));
    } catch (error) {
      logError('Failed to search notes', error, { query });
      context.update((state) => ({
        trees: {
          ...state.trees,
          notes: {
            ...(state.trees.notes || { children: [], expandedPaths: new Set() }),
            loading: false,
            searchQuery: query,
            loaded: false
          }
        }
      }));
    }
  };

  const searchFiles = async (basePath: string, query: string) => {
    context.update((state) => ({
      trees: {
        ...state.trees,
        [basePath]: {
          ...(state.trees[basePath] || { children: [], expandedPaths: new Set() }),
          loading: true,
          searchQuery: query
        }
      }
    }));

    try {
      const response = query
        ? await fetch(
            `/api/v1/files/search?basePath=${encodeURIComponent(basePath)}&query=${encodeURIComponent(query)}&limit=50`,
            { method: 'POST' }
          )
        : await fetch(`/api/v1/files?basePath=${encodeURIComponent(basePath)}`);
      if (!response.ok) {
        await handleFetchError(response);
      }
      const data = await response.json();
      const rawItems = data.items || data.children || [];
      const children = Array.isArray(rawItems) ? rawItems.filter(isFileNode) : [];
      context.update((state) => ({
        trees: {
          ...state.trees,
          [basePath]: {
            ...(state.trees[basePath] || { children: [], expandedPaths: new Set() }),
            children,
            loading: false,
            searchQuery: query,
            loaded: true
          }
        }
      }));
    } catch (error) {
      logError('Failed to search files', error, { basePath, query });
      context.update((state) => ({
        trees: {
          ...state.trees,
          [basePath]: {
            ...(state.trees[basePath] || { children: [], expandedPaths: new Set() }),
            loading: false,
            searchQuery: query,
            loaded: false
          }
        }
      }));
    }
  };

  return { searchNotes, searchFiles };
}
