/**
 * Files store for managing multiple file tree states
 */
import { writable, get } from 'svelte/store';
import type { FileNode, FileTreeState } from '$lib/types/file';
import { editorStore } from '$lib/stores/editor';
import { notesAPI } from '$lib/services/api';
import { getCachedData, invalidateCache, isCacheStale, setCachedData } from '$lib/utils/cache';

const NOTES_TREE_CACHE_KEY = 'notes.tree';
const WORKSPACE_TREE_CACHE_PREFIX = 'files.tree';
const TREE_CACHE_TTL = 30 * 60 * 1000;
const TREE_CACHE_VERSION = '1.0';
const EXPANDED_CACHE_PREFIX = 'files.expanded';
const EXPANDED_TTL = 7 * 24 * 60 * 60 * 1000;

const normalizeBasePath = (basePath: string) => (basePath === '.' ? 'workspace' : basePath);
const getTreeCacheKey = (basePath: string) =>
  basePath === 'notes' ? NOTES_TREE_CACHE_KEY : `${WORKSPACE_TREE_CACHE_PREFIX}.${normalizeBasePath(basePath)}`;
const getExpandedCacheKey = (basePath: string) =>
  `${EXPANDED_CACHE_PREFIX}.${normalizeBasePath(basePath)}`;

function applyExpandedPaths(nodes: FileNode[], expandedPaths: Set<string>): FileNode[] {
  return nodes.map((node) => {
    const expanded = node.type === 'directory' ? expandedPaths.has(node.path) : undefined;
    const children = node.children ? applyExpandedPaths(node.children, expandedPaths) : node.children;
    return {
      ...node,
      ...(expanded !== undefined ? { expanded } : {}),
      ...(children ? { children } : {})
    };
  });
}

function hasFilePath(nodes: FileNode[] | undefined, targetPath: string): boolean {
  if (!nodes) return false;
  for (const node of nodes) {
    if (node.type === 'file' && node.path === targetPath) return true;
    if (node.children && hasFilePath(node.children, targetPath)) return true;
  }
  return false;
}

function createFilesStore() {
  const { subscribe, set, update } = writable<FileTreeState>({
    trees: {}
  });

  return {
    subscribe,

    async load(basePath: string = 'documents', force: boolean = false) {
      // Get current state
      const currentState = get({ subscribe });
      const currentTree = currentState.trees[basePath];
      const expandedCache = getCachedData<string[]>(getExpandedCacheKey(basePath), {
        ttl: EXPANDED_TTL,
        version: TREE_CACHE_VERSION
      });
      const cachedExpandedPaths = new Set(expandedCache || []);

      // Skip if already loading
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
          update(state => ({
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
            this.revalidateInBackground(basePath, cachedExpandedPaths);
          }
          return;
        }

        // Skip if data already exists (prevent unnecessary reloads)
        if (currentTree?.children && currentTree.children.length > 0) {
          return;
        }

        // Skip if we've loaded before, even if empty
        if (currentTree?.loaded) {
          return;
        }
      }

      // Initialize tree if it doesn't exist
      update(state => ({
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
          ? '/api/notes/tree'
          : `/api/files?basePath=${basePath}`;
        const response = await fetch(endpoint);
        if (!response.ok) throw new Error('Failed to load files');

        const data = await response.json();
        const children = data.children || [];
        const cacheKey = getTreeCacheKey(basePath);
        setCachedData(cacheKey, children, { ttl: TREE_CACHE_TTL, version: TREE_CACHE_VERSION });
        update(state => ({
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
        update(state => ({
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
    },

    async revalidateInBackground(basePath: string, expandedPaths: Set<string>) {
      try {
        const endpoint = basePath === 'notes'
          ? '/api/notes/tree'
          : `/api/files?basePath=${basePath}`;
        const response = await fetch(endpoint);
        if (!response.ok) return;
        const data = await response.json();
        const children = data.children || [];
        setCachedData(getTreeCacheKey(basePath), children, {
          ttl: TREE_CACHE_TTL,
          version: TREE_CACHE_VERSION
        });
        update(state => ({
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
    },

    toggleExpanded(basePath: string, path: string) {
      update(state => {
        const tree = state.trees[basePath];
        if (!tree) return state;

        const newExpandedPaths = new Set(tree.expandedPaths);

        if (newExpandedPaths.has(path)) {
          newExpandedPaths.delete(path);
        } else {
          newExpandedPaths.add(path);
        }

        // Update the expanded state in the tree
        const updateNode = (node: FileNode): FileNode => {
          if (node.path === path) {
            return { ...node, expanded: newExpandedPaths.has(path) };
          }
          if (node.children) {
            return {
              ...node,
              children: node.children.map(updateNode)
            };
          }
          return node;
        };

        return {
          trees: {
            ...state.trees,
            [basePath]: {
              ...tree,
              expandedPaths: newExpandedPaths,
              children: tree.children.map(updateNode)
            }
          }
        };
      });
      const updatedTree = get({ subscribe }).trees[basePath];
      if (updatedTree) {
        setCachedData(getExpandedCacheKey(basePath), Array.from(updatedTree.expandedPaths), {
          ttl: EXPANDED_TTL,
          version: TREE_CACHE_VERSION
        });
      }
    },

    removeNode(basePath: string, path: string) {
      update(state => {
        const tree = state.trees[basePath];
        if (!tree) return state;

        const removeFromNodes = (nodes: FileNode[]): FileNode[] => {
          return nodes
            .filter(node => node.path !== path)
            .map(node => {
              if (!node.children) return node;
              return {
                ...node,
                children: removeFromNodes(node.children)
              };
            });
        };

        return {
          trees: {
            ...state.trees,
            [basePath]: {
              ...tree,
              children: removeFromNodes(tree.children || [])
            }
          }
        };
      });
      const updatedTree = get({ subscribe }).trees[basePath];
      if (updatedTree?.children) {
        setCachedData(getTreeCacheKey(basePath), updatedTree.children, {
          ttl: TREE_CACHE_TTL,
          version: TREE_CACHE_VERSION
        });
      }
    },

    addNoteNode(payload: { id: string; name: string; folder?: string; modified?: number }) {
      update(state => {
        const tree = state.trees['notes'] || { children: [], expandedPaths: new Set(), loading: false };
        const searchQuery = tree.searchQuery || '';
        if (searchQuery) {
          return state;
        }

        const folder = payload.folder || '';
        const parts = folder.split('/').filter(Boolean);
        const children = tree.children || [];
        let current = children;
        let currentPath = '';

        for (const part of parts) {
          currentPath = currentPath ? `${currentPath}/${part}` : part;
          let folderNode = current.find(
            node => node.type === 'directory' && node.path === `folder:${currentPath}`
          );
          if (!folderNode) {
            folderNode = {
              name: part,
              path: `folder:${currentPath}`,
              type: 'directory',
              children: [],
              expanded: false
            };
            current.push(folderNode);
          }
          if (!folderNode.children) {
            folderNode.children = [];
          }
          current = folderNode.children;
        }

        const fileNode: FileNode = {
          name: payload.name,
          path: payload.id,
          type: 'file',
          modified: payload.modified ? new Date(payload.modified * 1000).toISOString() : undefined
        };

        const existingIndex = current.findIndex(node => node.type === 'file' && node.path === payload.id);
        if (existingIndex >= 0) {
          current.splice(existingIndex, 1);
        }
        current.push(fileNode);

        const sortChildren = (node: { children?: FileNode[] }) => {
          if (!node.children) return;
          node.children.sort(
            (a, b) => Number(a.type !== 'directory') - Number(b.type !== 'directory') || a.name.localeCompare(b.name)
          );
          node.children.forEach(child => {
            if (child.type === 'directory') {
              sortChildren(child);
            }
          });
        };
        sortChildren({ children });

        return {
          trees: {
            ...state.trees,
            notes: {
              ...tree,
              children
            }
          }
        };
      });
      const updatedTree = get({ subscribe }).trees['notes'];
      if (updatedTree?.children) {
        setCachedData(getTreeCacheKey('notes'), updatedTree.children, {
          ttl: TREE_CACHE_TTL,
          version: TREE_CACHE_VERSION
        });
      }
    },

    reset() {
      const currentState = get({ subscribe });
      Object.keys(currentState.trees).forEach((basePath) => {
        invalidateCache(getTreeCacheKey(basePath));
        invalidateCache(getExpandedCacheKey(basePath));
      });
      set({ trees: {} });
    },

    async searchNotes(query: string) {
      update(state => ({
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
        update(state => ({
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
        console.error('Failed to search notes:', error);
        update(state => ({
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
    },

    async searchFiles(basePath: string, query: string) {
      update(state => ({
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
              `/api/files/search?basePath=${encodeURIComponent(basePath)}&query=${encodeURIComponent(query)}&limit=50`,
              { method: 'POST' }
            )
          : await fetch(`/api/files?basePath=${encodeURIComponent(basePath)}`);
        if (!response.ok) {
          throw new Error('Failed to search files');
        }
        const data = await response.json();
        update(state => ({
          trees: {
            ...state.trees,
            [basePath]: {
              ...(state.trees[basePath] || { children: [], expandedPaths: new Set() }),
              children: data.items || data.children || [],
              loading: false,
              searchQuery: query,
              loaded: true
            }
          }
        }));
      } catch (error) {
        console.error('Failed to search files:', error);
        update(state => ({
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
    }
  };
}

export const filesStore = createFilesStore();
