import { describe, expect, it } from 'vitest';
import type { FileNode } from '$lib/types/file';
import {
  applyExpandedPaths,
  hasFilePath,
  insertNoteIntoFolder,
  maxPinnedOrder,
  removeNodeFromTree,
  sortNodes,
  toFolderNodePath,
  updateFolderNodePaths,
  updateNoteInTree
} from '$lib/stores/tree/nodes';

describe('tree nodes helpers', () => {
  it('applies expanded paths', () => {
    const nodes: FileNode[] = [
      { name: 'Folder', path: toFolderNodePath('Folder'), type: 'directory', children: [] }
    ];
    const expanded = applyExpandedPaths(nodes, new Set([toFolderNodePath('Folder')]));
    expect(expanded[0].expanded).toBe(true);
  });

  it('detects file paths recursively', () => {
    const nodes: FileNode[] = [
      {
        name: 'Folder',
        path: toFolderNodePath('Folder'),
        type: 'directory',
        children: [{ name: 'Note', path: 'note-1', type: 'file' }]
      }
    ];
    expect(hasFilePath(nodes, 'note-1')).toBe(true);
    expect(hasFilePath(nodes, 'missing')).toBe(false);
  });

  it('sorts folders before files', () => {
    const nodes: FileNode[] = [
      { name: 'B', path: 'file-b', type: 'file' },
      { name: 'A', path: toFolderNodePath('A'), type: 'directory', children: [] }
    ];
    const sorted = sortNodes(nodes);
    expect(sorted[0].type).toBe('directory');
  });

  it('computes max pinned order', () => {
    const nodes: FileNode[] = [
      { name: 'A', path: 'file-a', type: 'file', pinned: true, pinned_order: 2 },
      { name: 'B', path: 'file-b', type: 'file', pinned: true, pinned_order: 5 }
    ];
    expect(maxPinnedOrder(nodes)).toBe(5);
  });

  it('updates note in tree', () => {
    const nodes: FileNode[] = [{ name: 'A', path: 'note-1', type: 'file' }];
    const result = updateNoteInTree(nodes, 'note-1', (node) => ({ ...node, name: 'Renamed' }));
    expect(result.changed).toBe(true);
    expect(result.nodes[0].name).toBe('Renamed');
  });

  it('removes node from tree', () => {
    const nodes: FileNode[] = [{ name: 'A', path: 'note-1', type: 'file' }];
    const result = removeNodeFromTree(nodes, 'note-1');
    expect(result.changed).toBe(true);
    expect(result.nodes).toHaveLength(0);
  });

  it('inserts note into folder path', () => {
    const nodes: FileNode[] = [];
    const inserted = insertNoteIntoFolder(nodes, { name: 'Note', path: 'note-1', type: 'file' }, 'Folder/Sub');
    expect(inserted[0].type).toBe('directory');
  });

  it('updates folder node paths', () => {
    const folder: FileNode = {
      name: 'Old',
      path: toFolderNodePath('Old'),
      type: 'directory',
      children: []
    };
    const updated = updateFolderNodePaths(folder, 'Old', 'New', 'New');
    expect(updated.path).toBe(toFolderNodePath('New'));
    expect(updated.name).toBe('New');
  });
});
