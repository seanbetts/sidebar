import type { FileNode } from '$lib/types/file';
import type { TreeStoreContext } from '$lib/stores/tree/types';
import { cacheExpanded, cacheTree } from '$lib/stores/tree/cache';
import {
  ensureFolderPath,
  insertFolderNode,
  insertNoteIntoFolder,
  maxPinnedOrder,
  removeNodeFromTree,
  sortNodes,
  toFolderNodePath,
  updateExpandedPathsForFolder,
  updateFolderNodePaths,
  updateNoteInTree
} from '$lib/stores/tree/nodes';

export function createNotesActions(context: TreeStoreContext) {
  const addNoteNode = (payload: {
    id: string;
    name: string;
    folder?: string;
    modified?: number;
    pinned?: boolean;
    pinned_order?: number | null;
    archived?: boolean;
  }) => {
    context.update((state) => {
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
          (node) => node.type === 'directory' && node.path === `folder:${currentPath}`
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
        modified: payload.modified ? new Date(payload.modified * 1000).toISOString() : undefined,
        pinned: payload.pinned,
        pinned_order: payload.pinned_order ?? null,
        archived: payload.archived
      };

      const existingIndex = current.findIndex((node) => node.type === 'file' && node.path === payload.id);
      if (existingIndex >= 0) {
        current.splice(existingIndex, 1);
      }
      current.push(fileNode);

      const sortedChildren = sortNodes(children);

      return {
        trees: {
          ...state.trees,
          notes: {
            ...tree,
            children: sortedChildren
          }
        }
      };
    });

    const updatedTree = context.getState().trees['notes'];
    if (updatedTree?.children) {
      cacheTree('notes', updatedTree.children);
    }
  };

  const updateNoteFields = (noteId: string, updates: Partial<FileNode>) => {
    context.update((state) => {
      const tree = state.trees['notes'];
      if (!tree?.children) return state;

      const result = updateNoteInTree(tree.children, noteId, (node) => ({
        ...node,
        ...updates
      }));
      if (!result.changed) return state;

      return {
        trees: {
          ...state.trees,
          notes: {
            ...tree,
            children: result.nodes
          }
        }
      };
    });

    const updatedTree = context.getState().trees['notes'];
    if (updatedTree?.children) {
      cacheTree('notes', updatedTree.children);
    }
  };

  const renameNoteNode = (noteId: string, newName: string) => {
    context.update((state) => {
      const tree = state.trees['notes'];
      if (!tree?.children) return state;

      const result = updateNoteInTree(tree.children, noteId, (node) => ({
        ...node,
        name: newName
      }));
      if (!result.changed) return state;

      return {
        trees: {
          ...state.trees,
          notes: {
            ...tree,
            children: result.nodes
          }
        }
      };
    });

    const updatedTree = context.getState().trees['notes'];
    if (updatedTree?.children) {
      cacheTree('notes', updatedTree.children);
    }
  };

  const setNotePinned = (noteId: string, pinned: boolean) => {
    context.update((state) => {
      const tree = state.trees['notes'];
      if (!tree?.children) return state;
      const nextPinnedOrder = pinned ? maxPinnedOrder(tree.children) + 1 : null;

      const result = updateNoteInTree(tree.children, noteId, (node) => ({
        ...node,
        pinned,
        ...(pinned ? { pinned_order: node.pinned_order ?? nextPinnedOrder } : { pinned_order: null })
      }));
      if (!result.changed) return state;

      return {
        trees: {
          ...state.trees,
          notes: {
            ...tree,
            children: result.nodes
          }
        }
      };
    });

    const updatedTree = context.getState().trees['notes'];
    if (updatedTree?.children) {
      cacheTree('notes', updatedTree.children);
    }
  };

  const setNotePinnedOrder = (order: string[]) => {
    context.update((state) => {
      const tree = state.trees['notes'];
      if (!tree?.children) return state;
      const orderMap = new Map(order.map((noteId, index) => [noteId, index]));

      let changed = false;
      const updateNodes = (nodes: FileNode[]): FileNode[] =>
        nodes.map((node) => {
          if (node.type === 'file' && orderMap.has(node.path)) {
            changed = true;
            return { ...node, pinned_order: orderMap.get(node.path) };
          }
          if (node.children) {
            const children = updateNodes(node.children);
            return children === node.children ? node : { ...node, children };
          }
          return node;
        });

      const nextChildren = updateNodes(tree.children);
      if (!changed) return state;

      return {
        trees: {
          ...state.trees,
          notes: {
            ...tree,
            children: nextChildren
          }
        }
      };
    });

    const updatedTree = context.getState().trees['notes'];
    if (updatedTree?.children) {
      cacheTree('notes', updatedTree.children);
    }
  };

  const moveNoteNode = (noteId: string, folder: string, options?: { archived?: boolean }) => {
    context.update((state) => {
      const tree = state.trees['notes'];
      if (!tree?.children) return state;
      const searchQuery = tree.searchQuery || '';
      const normalizedFolder = folder.replace(/^\/+|\/+$/g, '');

      if (searchQuery) {
        const result = updateNoteInTree(tree.children, noteId, (node) => ({
          ...node,
          ...(options?.archived !== undefined ? { archived: options.archived } : {})
        }));
        if (!result.changed) return state;
        return {
          trees: {
            ...state.trees,
            notes: {
              ...tree,
              children: result.nodes
            }
          }
        };
      }

      const removal = removeNodeFromTree(tree.children, noteId);
      if (!removal.removed) return state;

      const archived = options?.archived ?? (normalizedFolder === 'Archive');
      const movedNode: FileNode = {
        ...removal.removed,
        archived
      };
      const updatedChildren = insertNoteIntoFolder(removal.nodes, movedNode, normalizedFolder);

      return {
        trees: {
          ...state.trees,
          notes: {
            ...tree,
            children: updatedChildren
          }
        }
      };
    });

    const updatedTree = context.getState().trees['notes'];
    if (updatedTree?.children) {
      cacheTree('notes', updatedTree.children);
    }
  };

  const archiveNoteNode = (noteId: string, archived: boolean) => {
    const targetFolder = archived ? 'Archive' : '';
    moveNoteNode(noteId, targetFolder, { archived });
  };

  const addFolderNode = (path: string) => {
    context.update((state) => {
      const tree = state.trees['notes'] || { children: [], expandedPaths: new Set(), loading: false };
      const searchQuery = tree.searchQuery || '';
      if (searchQuery) {
        return state;
      }
      const normalized = path.replace(/^\/+|\/+$/g, '');
      if (!normalized) return state;

      const updatedChildren = ensureFolderPath(tree.children || [], normalized, { folderMarker: true });
      if (updatedChildren === tree.children) return state;

      return {
        trees: {
          ...state.trees,
          notes: {
            ...tree,
            children: updatedChildren
          }
        }
      };
    });

    const updatedTree = context.getState().trees['notes'];
    if (updatedTree?.children) {
      cacheTree('notes', updatedTree.children);
    }
  };

  const renameFolderNode = (oldPath: string, newName: string) => {
    context.update((state) => {
      const tree = state.trees['notes'];
      if (!tree?.children) return state;
      const searchQuery = tree.searchQuery || '';
      if (searchQuery) return state;

      const normalizedOld = oldPath.replace(/^\/+|\/+$/g, '');
      if (!normalizedOld) return state;

      const parentPath = normalizedOld.split('/').slice(0, -1).join('/');
      const newPath = parentPath ? `${parentPath}/${newName}` : newName;
      const removal = removeNodeFromTree(tree.children, toFolderNodePath(normalizedOld));
      if (!removal.removed) return state;

      const updatedNode = updateFolderNodePaths(removal.removed, normalizedOld, newPath, newName);
      const updatedChildren = insertFolderNode(removal.nodes, updatedNode, parentPath);
      const updatedExpandedPaths = updateExpandedPathsForFolder(tree.expandedPaths, normalizedOld, newPath);

      return {
        trees: {
          ...state.trees,
          notes: {
            ...tree,
            children: updatedChildren,
            expandedPaths: updatedExpandedPaths
          }
        }
      };
    });

    const updatedTree = context.getState().trees['notes'];
    if (updatedTree?.children) {
      cacheTree('notes', updatedTree.children);
      cacheExpanded('notes', updatedTree.expandedPaths);
    }
  };

  const moveFolderNode = (oldPath: string, newParent: string) => {
    context.update((state) => {
      const tree = state.trees['notes'];
      if (!tree?.children) return state;
      const searchQuery = tree.searchQuery || '';
      if (searchQuery) return state;

      const normalizedOld = oldPath.replace(/^\/+|\/+$/g, '');
      if (!normalizedOld) return state;
      const normalizedParent = newParent.replace(/^\/+|\/+$/g, '');
      const leafName = normalizedOld.split('/').slice(-1)[0];
      const newPath = normalizedParent ? `${normalizedParent}/${leafName}` : leafName;

      const removal = removeNodeFromTree(tree.children, toFolderNodePath(normalizedOld));
      if (!removal.removed) return state;

      const updatedNode = updateFolderNodePaths(removal.removed, normalizedOld, newPath);
      const updatedChildren = insertFolderNode(removal.nodes, updatedNode, normalizedParent);
      const updatedExpandedPaths = updateExpandedPathsForFolder(tree.expandedPaths, normalizedOld, newPath);

      return {
        trees: {
          ...state.trees,
          notes: {
            ...tree,
            children: updatedChildren,
            expandedPaths: updatedExpandedPaths
          }
        }
      };
    });

    const updatedTree = context.getState().trees['notes'];
    if (updatedTree?.children) {
      cacheTree('notes', updatedTree.children);
      cacheExpanded('notes', updatedTree.expandedPaths);
    }
  };

  return {
    addNoteNode,
    updateNoteFields,
    renameNoteNode,
    setNotePinned,
    setNotePinnedOrder,
    moveNoteNode,
    archiveNoteNode,
    addFolderNode,
    renameFolderNode,
    moveFolderNode
  };
}
