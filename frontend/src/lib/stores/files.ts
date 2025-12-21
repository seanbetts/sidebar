/**
 * Files store for managing multiple file tree states
 */
import { writable } from 'svelte/store';
import type { FileNode, FileTreeState, SingleFileTree } from '$lib/types/file';

function createFilesStore() {
  const { subscribe, set, update } = writable<FileTreeState>({
    trees: {}
  });

  return {
    subscribe,

    async load(basePath: string = 'documents') {
      // Initialize tree if it doesn't exist
      update(state => ({
        trees: {
          ...state.trees,
          [basePath]: {
            ...(state.trees[basePath] || { children: [], expandedPaths: new Set() }),
            loading: true
          }
        }
      }));

      try {
        const response = await fetch(`/api/files?basePath=${basePath}`);
        if (!response.ok) throw new Error('Failed to load files');

        const data = await response.json();
        update(state => ({
          trees: {
            ...state.trees,
            [basePath]: {
              ...state.trees[basePath],
              children: data.children || [],
              loading: false
            }
          }
        }));
      } catch (error) {
        console.error(`Failed to load file tree for ${basePath}:`, error);
        update(state => ({
          trees: {
            ...state.trees,
            [basePath]: {
              ...state.trees[basePath],
              loading: false
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

    reset() {
      set({ trees: {} });
    }
  };
}

export const filesStore = createFilesStore();
