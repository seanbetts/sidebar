import type { FileNode } from '$lib/types/file';

export const toFolderNodePath = (path: string) => `folder:${path}`;

export function applyExpandedPaths(nodes: FileNode[], expandedPaths: Set<string>): FileNode[] {
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

export function hasFilePath(nodes: FileNode[] | undefined, targetPath: string): boolean {
  if (!nodes) return false;
  for (const node of nodes) {
    if (node.type === 'file' && node.path === targetPath) return true;
    if (node.children && hasFilePath(node.children, targetPath)) return true;
  }
  return false;
}

export function sortNodes(nodes: FileNode[]): FileNode[] {
  const sorted = [...nodes].sort(
    (a, b) => Number(a.type !== 'directory') - Number(b.type !== 'directory') || a.name.localeCompare(b.name)
  );
  return sorted.map((node) => {
    if (node.type !== 'directory' || !node.children) return node;
    return { ...node, children: sortNodes(node.children) };
  });
}

export function maxPinnedOrder(nodes: FileNode[]): number {
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

export function updateNoteInTree(
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

export function removeNodeFromTree(
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

export function insertNoteIntoFolder(nodes: FileNode[], noteNode: FileNode, folderPath: string): FileNode[] {
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

export function updateFolderNodePaths(
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

export function insertFolderNode(nodes: FileNode[], folderNode: FileNode, parentPath: string): FileNode[] {
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

export function ensureFolderPath(
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

export function updateExpandedPathsForFolder(
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

export function updateWorkspaceNodePaths(node: FileNode, oldPrefix: string, newPrefix: string, renameTo?: string): FileNode {
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

export function insertWorkspaceNode(nodes: FileNode[], nodeToInsert: FileNode, parentPath: string): FileNode[] {
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

export function updateExpandedPathsForWorkspaceFolder(
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
