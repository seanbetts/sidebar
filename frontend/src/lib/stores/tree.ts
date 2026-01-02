/**
 * Tree store for managing notes and workspace file trees.
 */
import { writable, get } from 'svelte/store';
import type { FileNode, FileTreeState } from '$lib/types/file';
import { editorStore } from '$lib/stores/editor';
import { notesAPI } from '$lib/services/api';
import { getCachedData, invalidateCache, isCacheStale, setCachedData } from '$lib/utils/cache';

const NOTES_TREE_CACHE_KEY = 'notes.tree';
const WORKSPACE_TREE_CACHE_PREFIX = 'files.tree';
const TREE_CACHE_TTL = 30 * 60 * 1000;
const TREE_CACHE_VERSION = '1.1';
const EXPANDED_CACHE_PREFIX = 'files.expanded';
const EXPANDED_TTL = 7 * 24 * 60 * 60 * 1000;

const normalizeBasePath = (basePath: string) => (basePath === '.' ? 'workspace' : basePath);
const getTreeCacheKey = (basePath: string) =>
  basePath === 'notes' ? NOTES_TREE_CACHE_KEY : `${WORKSPACE_TREE_CACHE_PREFIX}.${normalizeBasePath(basePath)}`;
const getExpandedCacheKey = (basePath: string) =>
  `${EXPANDED_CACHE_PREFIX}.${normalizeBasePath(basePath)}`;
const toFolderPath = (path: string) => path.replace(/^folder:/, '');
const toFolderNodePath = (path: string) => `folder:${path}`;

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

function sortNodes(nodes: FileNode[]): FileNode[] {
  const sorted = [...nodes].sort(
    (a, b) => Number(a.type !== 'directory') - Number(b.type !== 'directory') || a.name.localeCompare(b.name)
  );
  return sorted.map((node) => {
    if (node.type !== 'directory' || !node.children) return node;
    return { ...node, children: sortNodes(node.children) };
  });
}

function maxPinnedOrder(nodes: FileNode[]): number {
  let maxOrder = -1;
  for (const node of nodes) {
    if (node.type === 'file' && node.pinned) {
      const value = typeof node.pinned_order === 'number' ? node.pinned_order : -1;
      if (value > maxOrder) maxOrder = value;
    }
    if (node.children) {
      maxOrder = Math.max(maxOrder, maxPinnedOrder(node.children));
    }
  }
  return maxOrder;
}


function updateNoteInTree(
  nodes: FileNode[],
  noteId: string,
  updater: (node: FileNode) => FileNode
): { nodes: FileNode[]; changed: boolean } {
  let changed = false;
  const updated = nodes.map((node) => {
    if (node.type === 'file' && node.path === noteId) {
      changed = true;
      return updater(node);
    }
    if (node.children) {
      const result = updateNoteInTree(node.children, noteId, updater);
      if (result.changed) {
        changed = true;
        return { ...node, children: result.nodes };
      }
    }
    return node;
  });
  return { nodes: changed ? updated : nodes, changed };
}

function removeNodeFromTree(
  nodes: FileNode[],
  targetPath: string
): { nodes: FileNode[]; removed?: FileNode; changed: boolean } {
  let removed: FileNode | undefined;
  let changed = false;
  const updated = [];

  for (const node of nodes) {
    if (node.path === targetPath) {
      removed = node;
      changed = true;
      continue;
    }
    if (node.children) {
      const result = removeNodeFromTree(node.children, targetPath);
      if (result.changed) {
        changed = true;
        if (result.removed) {
          removed = result.removed;
        }
        updated.push({ ...node, children: result.nodes });
        continue;
      }
    }
    updated.push(node);
  }

  return { nodes: changed ? updated : nodes, removed, changed };
}

function insertNoteIntoFolder(nodes: FileNode[], noteNode: FileNode, folderPath: string): FileNode[] {
  const parts = folderPath.split('/').filter(Boolean);
  const insertIntoList = (items: FileNode[]) => {
    const filtered = items.filter((item) => item.path !== noteNode.path);
    return sortNodes([...filtered, noteNode]);
  };

  const insertRecursive = (items: FileNode[], remaining: string[], prefix: string): FileNode[] => {
    if (remaining.length === 0) {
      return insertIntoList(items);
    }

    const [part, ...rest] = remaining;
    const currentPath = prefix ? `${prefix}/${part}` : part;
    const targetPath = toFolderNodePath(currentPath);
    let found = false;

    const nextItems = items.map((item) => {
      if (item.type !== 'directory' || item.path !== targetPath) {
        return item;
      }
      found = true;
      const children = item.children || [];
      const updatedChildren = insertRecursive(children, rest, currentPath);
      return { ...item, children: updatedChildren };
    });

    if (!found) {
      const newFolder: FileNode = {
        name: part,
        path: targetPath,
        type: 'directory',
        children: [],
        expanded: false
      };
      newFolder.children = insertRecursive([], rest, currentPath);
      return sortNodes([...nextItems, newFolder]);
    }

    return sortNodes(nextItems);
  };

  return parts.length === 0 ? insertIntoList(nodes) : insertRecursive(nodes, parts, '');
}

function updateFolderNodePaths(
  node: FileNode,
  oldPrefix: string,
  newPrefix: string,
  renameTo?: string
): FileNode {
  if (node.type !== 'directory') return node;

  const oldToken = toFolderNodePath(oldPrefix);
  const newToken = toFolderNodePath(newPrefix);
  const matches = node.path === oldToken || node.path.startsWith(`${oldToken}/`);
  const updatedPath = matches ? node.path.replace(oldToken, newToken) : node.path;
  const updatedName = matches && renameTo && node.path === oldToken ? renameTo : node.name;

  const children = node.children
    ? node.children.map((child) =>
        child.type === 'directory' ? updateFolderNodePaths(child, oldPrefix, newPrefix) : child
      )
    : node.children;

  if (updatedPath === node.path && updatedName === node.name && children === node.children) {
    return node;
  }

  return {
    ...node,
    path: updatedPath,
    name: updatedName,
    children
  };
}

function insertFolderNode(
  nodes: FileNode[],
  folderNode: FileNode,
  parentPath: string
): FileNode[] {
  const parts = parentPath.split('/').filter(Boolean);

  const insertIntoList = (items: FileNode[]) => {
    const filtered = items.filter((item) => item.path !== folderNode.path);
    return sortNodes([...filtered, folderNode]);
  };

  const insertRecursive = (items: FileNode[], remaining: string[], prefix: string): FileNode[] => {
    if (remaining.length === 0) {
      return insertIntoList(items);
    }

    const [part, ...rest] = remaining;
    const currentPath = prefix ? `${prefix}/${part}` : part;
    const targetPath = toFolderNodePath(currentPath);
    let found = false;

    const nextItems = items.map((item) => {
      if (item.type !== 'directory' || item.path !== targetPath) {
        return item;
      }
      found = true;
      const children = item.children || [];
      const updatedChildren = insertRecursive(children, rest, currentPath);
      return { ...item, children: updatedChildren };
    });

    if (!found) {
      const newFolder: FileNode = {
        name: part,
        path: targetPath,
        type: 'directory',
        children: [],
        expanded: false
      };
      newFolder.children = insertRecursive([], rest, currentPath);
      return sortNodes([...nextItems, newFolder]);
    }

    return sortNodes(nextItems);
  };

  return parts.length === 0 ? insertIntoList(nodes) : insertRecursive(nodes, parts, '');
}

function ensureFolderPath(
  nodes: FileNode[],
  folderPath: string,
  { folderMarker }: { folderMarker: boolean }
): FileNode[] {
  const parts = folderPath.split('/').filter(Boolean);
  if (parts.length === 0) return nodes;

  const ensureRecursive = (items: FileNode[], remaining: string[], prefix: string): FileNode[] => {
    const [part, ...rest] = remaining;
    const currentPath = prefix ? `${prefix}/${part}` : part;
    const targetPath = toFolderNodePath(currentPath);
    let found = false;

    const nextItems = items.map((item) => {
      if (item.type !== 'directory' || item.path !== targetPath) {
        return item;
      }
      found = true;
      if (rest.length === 0 && folderMarker && !item.folderMarker) {
        return { ...item, folderMarker: true };
      }
      if (!item.children) {
        return { ...item, children: [] };
      }
      const updatedChildren = rest.length ? ensureRecursive(item.children, rest, currentPath) : item.children;
      if (updatedChildren !== item.children) {
        return { ...item, children: updatedChildren };
      }
      return item;
    });

    if (!found) {
      const newFolder: FileNode = {
        name: part,
        path: targetPath,
        type: 'directory',
        children: [],
        expanded: false,
        ...(rest.length === 0 && folderMarker ? { folderMarker: true } : {})
      };
      newFolder.children = rest.length ? ensureRecursive([], rest, currentPath) : [];
      return sortNodes([...nextItems, newFolder]);
    }

    return sortNodes(nextItems);
  };

  return ensureRecursive(nodes, parts, '');
}

function updateExpandedPathsForFolder(
  expandedPaths: Set<string>,
  oldPath: string,
  newPath: string
): Set<string> {
  const updated = new Set<string>();
  const oldToken = toFolderNodePath(oldPath);
  const newToken = toFolderNodePath(newPath);

  expandedPaths.forEach((value) => {
    if (value === oldToken || value.startsWith(`${oldToken}/`)) {
      updated.add(value.replace(oldToken, newToken));
    } else {
      updated.add(value);
    }
  });

  return updated;
}

function updateWorkspaceNodePaths(node: FileNode, oldPrefix: string, newPrefix: string, renameTo?: string): FileNode {
  const matches = node.path === oldPrefix || node.path.startsWith(`${oldPrefix}/`);
  const updatedPath = matches ? node.path.replace(oldPrefix, newPrefix) : node.path;
  const updatedName = matches && renameTo && node.path === oldPrefix ? renameTo : node.name;
  const children = node.children
    ? node.children.map((child) => updateWorkspaceNodePaths(child, oldPrefix, newPrefix))
    : node.children;

  if (updatedPath === node.path && updatedName === node.name && children === node.children) {
    return node;
  }

  return {
    ...node,
    path: updatedPath,
    name: updatedName,
    children
  };
}

function insertWorkspaceNode(nodes: FileNode[], nodeToInsert: FileNode, parentPath: string): FileNode[] {
  const parts = parentPath.split('/').filter(Boolean);

  const insertIntoList = (items: FileNode[]) => {
    const filtered = items.filter((item) => item.path !== nodeToInsert.path);
    return sortNodes([...filtered, nodeToInsert]);
  };

  const insertRecursive = (items: FileNode[], remaining: string[], prefix: string): FileNode[] => {
    if (remaining.length === 0) {
      return insertIntoList(items);
    }

    const [part, ...rest] = remaining;
    const currentPath = prefix ? `${prefix}/${part}` : part;
    let found = false;

    const nextItems = items.map((item) => {
      if (item.type !== 'directory' || item.path !== currentPath) {
        return item;
      }
      found = true;
      const children = item.children || [];
      const updatedChildren = insertRecursive(children, rest, currentPath);
      return { ...item, children: updatedChildren };
    });

    if (!found) {
      const newFolder: FileNode = {
        name: part,
        path: currentPath,
        type: 'directory',
        children: [],
        expanded: false
      };
      newFolder.children = insertRecursive([], rest, currentPath);
      return sortNodes([...nextItems, newFolder]);
    }

    return sortNodes(nextItems);
  };

  return parts.length === 0 ? insertIntoList(nodes) : insertRecursive(nodes, parts, '');
}

function updateExpandedPathsForWorkspaceFolder(
  expandedPaths: Set<string>,
  oldPath: string,
  newPath: string
): Set<string> {
  const updated = new Set<string>();
  expandedPaths.forEach((value) => {
    if (value === oldPath || value.startsWith(`${oldPath}/`)) {
      updated.add(value.replace(oldPath, newPath));
    } else {
      updated.add(value);
    }
  });
  return updated;
}

function createTreeStore() {
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

    addNoteNode(payload: {
      id: string;
      name: string;
      folder?: string;
      modified?: number;
      pinned?: boolean;
      pinned_order?: number | null;
      archived?: boolean;
    }) {
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
          modified: payload.modified ? new Date(payload.modified * 1000).toISOString() : undefined,
          pinned: payload.pinned,
          pinned_order: payload.pinned_order ?? null,
          archived: payload.archived
        };

        const existingIndex = current.findIndex(node => node.type === 'file' && node.path === payload.id);
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
      const updatedTree = get({ subscribe }).trees['notes'];
      if (updatedTree?.children) {
        setCachedData(getTreeCacheKey('notes'), updatedTree.children, {
          ttl: TREE_CACHE_TTL,
          version: TREE_CACHE_VERSION
        });
      }
    },

    updateNoteFields(noteId: string, updates: Partial<FileNode>) {
      update(state => {
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
      const updatedTree = get({ subscribe }).trees['notes'];
      if (updatedTree?.children) {
        setCachedData(getTreeCacheKey('notes'), updatedTree.children, {
          ttl: TREE_CACHE_TTL,
          version: TREE_CACHE_VERSION
        });
      }
    },

    renameNoteNode(noteId: string, newName: string) {
      update(state => {
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
      const updatedTree = get({ subscribe }).trees['notes'];
      if (updatedTree?.children) {
        setCachedData(getTreeCacheKey('notes'), updatedTree.children, {
          ttl: TREE_CACHE_TTL,
          version: TREE_CACHE_VERSION
        });
      }
    },

    setNotePinned(noteId: string, pinned: boolean) {
      update(state => {
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
      const updatedTree = get({ subscribe }).trees['notes'];
      if (updatedTree?.children) {
        setCachedData(getTreeCacheKey('notes'), updatedTree.children, {
          ttl: TREE_CACHE_TTL,
          version: TREE_CACHE_VERSION
        });
      }
    },

    setNotePinnedOrder(order: string[]) {
      update(state => {
        const tree = state.trees['notes'];
        if (!tree?.children) return state;
        const orderMap = new Map(order.map((noteId, index) => [noteId, index]));

        let changed = false;
        const updateNodes = (nodes: FileNode[]): FileNode[] =>
          nodes.map(node => {
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
      const updatedTree = get({ subscribe }).trees['notes'];
      if (updatedTree?.children) {
        setCachedData(getTreeCacheKey('notes'), updatedTree.children, {
          ttl: TREE_CACHE_TTL,
          version: TREE_CACHE_VERSION
        });
      }
    },

    moveNoteNode(noteId: string, folder: string, options?: { archived?: boolean }) {
      update(state => {
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
      const updatedTree = get({ subscribe }).trees['notes'];
      if (updatedTree?.children) {
        setCachedData(getTreeCacheKey('notes'), updatedTree.children, {
          ttl: TREE_CACHE_TTL,
          version: TREE_CACHE_VERSION
        });
      }
    },

    archiveNoteNode(noteId: string, archived: boolean) {
      const targetFolder = archived ? 'Archive' : '';
      this.moveNoteNode(noteId, targetFolder, { archived });
    },

    addFolderNode(path: string) {
      update(state => {
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
      const updatedTree = get({ subscribe }).trees['notes'];
      if (updatedTree?.children) {
        setCachedData(getTreeCacheKey('notes'), updatedTree.children, {
          ttl: TREE_CACHE_TTL,
          version: TREE_CACHE_VERSION
        });
      }
    },

    renameFolderNode(oldPath: string, newName: string) {
      update(state => {
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
      const updatedTree = get({ subscribe }).trees['notes'];
      if (updatedTree?.children) {
        setCachedData(getTreeCacheKey('notes'), updatedTree.children, {
          ttl: TREE_CACHE_TTL,
          version: TREE_CACHE_VERSION
        });
        setCachedData(getExpandedCacheKey('notes'), Array.from(updatedTree.expandedPaths), {
          ttl: EXPANDED_TTL,
          version: TREE_CACHE_VERSION
        });
      }
    },

    moveFolderNode(oldPath: string, newParent: string) {
      update(state => {
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
      const updatedTree = get({ subscribe }).trees['notes'];
      if (updatedTree?.children) {
        setCachedData(getTreeCacheKey('notes'), updatedTree.children, {
          ttl: TREE_CACHE_TTL,
          version: TREE_CACHE_VERSION
        });
        setCachedData(getExpandedCacheKey('notes'), Array.from(updatedTree.expandedPaths), {
          ttl: EXPANDED_TTL,
          version: TREE_CACHE_VERSION
        });
      }
    },

    renameWorkspaceNode(basePath: string, path: string, newName: string) {
      if (basePath === 'notes') return;
      update(state => {
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
      const updatedTree = get({ subscribe }).trees[basePath];
      if (updatedTree?.children) {
        setCachedData(getTreeCacheKey(basePath), updatedTree.children, {
          ttl: TREE_CACHE_TTL,
          version: TREE_CACHE_VERSION
        });
        setCachedData(getExpandedCacheKey(basePath), Array.from(updatedTree.expandedPaths), {
          ttl: EXPANDED_TTL,
          version: TREE_CACHE_VERSION
        });
      }
    },

    moveWorkspaceNode(basePath: string, path: string, destination: string) {
      if (basePath === 'notes') return;
      update(state => {
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
      const updatedTree = get({ subscribe }).trees[basePath];
      if (updatedTree?.children) {
        setCachedData(getTreeCacheKey(basePath), updatedTree.children, {
          ttl: TREE_CACHE_TTL,
          version: TREE_CACHE_VERSION
        });
        setCachedData(getExpandedCacheKey(basePath), Array.from(updatedTree.expandedPaths), {
          ttl: EXPANDED_TTL,
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
        const rawItems = data.items || data.children || [];
        update(state => ({
          trees: {
            ...state.trees,
            [basePath]: {
              ...(state.trees[basePath] || { children: [], expandedPaths: new Set() }),
              children: rawItems,
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

export const treeStore = createTreeStore();
