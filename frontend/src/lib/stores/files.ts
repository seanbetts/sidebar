/**
 * Files store for managing multiple file tree states
 */
import { writable, get } from 'svelte/store';
import type { FileNode, FileTreeState } from '$lib/types/file';
import { editorStore } from '$lib/stores/editor';
import { notesAPI } from '$lib/services/api';

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

      // Skip if already loading
      if (currentTree?.loading) {
        return;
      }

      if (!force) {
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
            ...(state.trees[basePath] || { children: [], expandedPaths: new Set() }),
            loading: true,
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
        update(state => ({
          trees: {
            ...state.trees,
            [basePath]: {
              ...state.trees[basePath],
              children,
              loading: false,
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
              searchQuery: '',
              loaded: false
            }
          }
        }));
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
    },

    reset() {
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
