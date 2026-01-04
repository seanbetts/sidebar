import type { TreeStoreContext } from '$lib/stores/tree/types';
import { cacheExpanded, cacheTree } from '$lib/stores/tree/cache';
import {
  insertWorkspaceNode,
  removeNodeFromTree,
  updateExpandedPathsForWorkspaceFolder,
  updateWorkspaceNodePaths
} from '$lib/stores/tree/nodes';

export function createWorkspaceActions(context: TreeStoreContext) {
  const renameWorkspaceNode = (basePath: string, path: string, newName: string) => {
    if (basePath === 'notes') return;
    context.update((state) => {
      const tree = state.trees[basePath];
      if (!tree?.children) return state;
      const searchQuery = tree.searchQuery || '';
      if (searchQuery) return state;

      const normalizedPath = path.replace(/^\/+|\/+$/g, '');
      if (!normalizedPath) return state;
      const parentPath = normalizedPath.split('/').slice(0, -1).join('/');
      const newPath = parentPath ? `${parentPath}/${newName}` : newName;

      const removal = removeNodeFromTree(tree.children, normalizedPath);
      if (!removal.removed) return state;

      const updatedNode = removal.removed.type === 'directory'
        ? updateWorkspaceNodePaths(removal.removed, normalizedPath, newPath, newName)
        : { ...removal.removed, name: newName, path: newPath };
      const updatedChildren = insertWorkspaceNode(removal.nodes, updatedNode, parentPath);
      const updatedExpandedPaths = removal.removed.type === 'directory'
        ? updateExpandedPathsForWorkspaceFolder(tree.expandedPaths, normalizedPath, newPath)
        : tree.expandedPaths;

      return {
        trees: {
          ...state.trees,
          [basePath]: {
            ...tree,
            children: updatedChildren,
            expandedPaths: updatedExpandedPaths
          }
        }
      };
    });

    const updatedTree = context.getState().trees[basePath];
    if (updatedTree?.children) {
      cacheTree(basePath, updatedTree.children);
      cacheExpanded(basePath, updatedTree.expandedPaths);
    }
  };

  const moveWorkspaceNode = (basePath: string, path: string, destination: string) => {
    if (basePath === 'notes') return;
    context.update((state) => {
      const tree = state.trees[basePath];
      if (!tree?.children) return state;
      const searchQuery = tree.searchQuery || '';
      if (searchQuery) return state;

      const normalizedPath = path.replace(/^\/+|\/+$/g, '');
      if (!normalizedPath) return state;
      const normalizedDestination = destination.replace(/^\/+|\/+$/g, '');
      const nodeName = normalizedPath.split('/').slice(-1)[0];
      const newPath = normalizedDestination ? `${normalizedDestination}/${nodeName}` : nodeName;

      const removal = removeNodeFromTree(tree.children, normalizedPath);
      if (!removal.removed) return state;

      const updatedNode = removal.removed.type === 'directory'
        ? updateWorkspaceNodePaths(removal.removed, normalizedPath, newPath)
        : { ...removal.removed, path: newPath };
      const updatedChildren = insertWorkspaceNode(removal.nodes, updatedNode, normalizedDestination);
      const updatedExpandedPaths = removal.removed.type === 'directory'
        ? updateExpandedPathsForWorkspaceFolder(tree.expandedPaths, normalizedPath, newPath)
        : tree.expandedPaths;

      return {
        trees: {
          ...state.trees,
          [basePath]: {
            ...tree,
            children: updatedChildren,
            expandedPaths: updatedExpandedPaths
          }
        }
      };
    });

    const updatedTree = context.getState().trees[basePath];
    if (updatedTree?.children) {
      cacheTree(basePath, updatedTree.children);
      cacheExpanded(basePath, updatedTree.expandedPaths);
    }
  };

  return { renameWorkspaceNode, moveWorkspaceNode };
}
