import type { FileNode } from '$lib/types/file';
import type { TreeStoreContext } from '$lib/stores/tree/types';
import { cacheExpanded, cacheTree } from '$lib/stores/tree/cache';

export function createMutationActions(context: TreeStoreContext) {
  const toggleExpanded = (basePath: string, path: string) => {
    context.update((state) => {
      const tree = state.trees[basePath];
      if (!tree) return state;

      const newExpandedPaths = new Set(tree.expandedPaths);

      if (newExpandedPaths.has(path)) {
        newExpandedPaths.delete(path);
      } else {
        newExpandedPaths.add(path);
      }

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

    const updatedTree = context.getState().trees[basePath];
    if (updatedTree) {
      cacheExpanded(basePath, updatedTree.expandedPaths);
    }
  };

  const removeNode = (basePath: string, path: string) => {
    context.update((state) => {
      const tree = state.trees[basePath];
      if (!tree) return state;

      const removeFromNodes = (nodes: FileNode[]): FileNode[] => {
        return nodes
          .filter((node) => node.path !== path)
          .map((node) => {
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

    const updatedTree = context.getState().trees[basePath];
    if (updatedTree?.children) {
      cacheTree(basePath, updatedTree.children);
    }
  };

  return { toggleExpanded, removeNode };
}
