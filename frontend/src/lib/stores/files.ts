/**
 * Files store for managing multiple file tree states
 */
import { writable, get } from 'svelte/store';
import type { FileNode, FileTreeState, SingleFileTree } from '$lib/types/file';
import { editorStore } from '$lib/stores/editor';

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
        const children = data.children || [];
        update(state => ({
          trees: {
            ...state.trees,
            [basePath]: {
              ...state.trees[basePath],
              children,
              loading: false
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
