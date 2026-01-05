import { get } from 'svelte/store';
import type { FileNode } from '$lib/types/file';
import type { EditorStore } from '$lib/stores/editor';
import type { TreeStore } from '$lib/stores/tree/store';
import { dispatchCacheEvent } from '$lib/utils/cacheEvents';
import { logError } from '$lib/utils/errorHandling';

const NOTE_ARCHIVE_NAME = 'Archive';

type FileActionsContext = {
  getNode: () => FileNode;
  getBasePath: () => string;
  getHideExtensions: () => boolean;
  getEditedName: () => string;
  setEditedName: (value: string) => void;
  setIsEditing: (value: boolean) => void;
  requestDelete: () => void;
  setFolderOptions: (value: { label: string; value: string; depth: number }[]) => void;
  getDisplayName: () => string;
  editorStore: EditorStore;
  treeStore: TreeStore;
};

const toFolderPath = (path: string) => path.replace(/^folder:/, '');

/**
 * Build file tree action handlers for rename, move, and delete flows.
 *
 * @param ctx - Context with file tree state and UI setters.
 * @returns Action handlers for file tree interactions.
 */
export function useFileActions(ctx: FileActionsContext) {
  const buildFolderOptions = (excludePath?: string) => {
    const basePath = ctx.getBasePath();
    const tree = get(ctx.treeStore).trees[basePath];
    const rootChildren = tree?.children || [];
    const rootLabel = basePath === 'notes' ? 'Notes' : 'Workspace';
    const options: { label: string; value: string; depth: number }[] = [
      { label: rootLabel, value: '', depth: 0 }
    ];

    const walk = (nodes: FileNode[], depth: number) => {
      for (const child of nodes) {
        if (child.type !== 'directory') continue;
        if (basePath === 'notes' && child.name === NOTE_ARCHIVE_NAME) continue;
        const folderPath = toFolderPath(child.path);
        if (excludePath && (folderPath === excludePath || folderPath.startsWith(`${excludePath}/`))) {
          if (child.children?.length) {
            walk(child.children, depth + 1);
          }
          continue;
        }
        options.push({ label: child.name, value: folderPath, depth });
        if (child.children?.length) {
          walk(child.children, depth + 1);
        }
      }
    };

    walk(rootChildren, 1);
    ctx.setFolderOptions(options);
  };

  const startRename = () => {
    const node = ctx.getNode();
    if (ctx.getHideExtensions() && node.type === 'file') {
      ctx.setEditedName(node.name.replace(/\.[^/.]+$/, ''));
    } else {
      ctx.setEditedName(node.name);
    }
    ctx.setIsEditing(true);
  };

  const saveRename = async () => {
    const node = ctx.getNode();
    const basePath = ctx.getBasePath();
    const trimmed = ctx.getEditedName().trim();
    if (trimmed && trimmed !== node.name) {
      try {
        let newName = trimmed;
        if (ctx.getHideExtensions() && node.type === 'file') {
          const extension = node.name.match(/\.[^/.]+$/)?.[0] || '';
          if (!newName.endsWith(extension)) {
            newName += extension;
          }
        }

        const response = basePath === 'notes'
          ? await fetch(
              node.type === 'directory'
                ? '/api/v1/notes/folders/rename'
                : `/api/v1/notes/${node.path}/rename`,
              {
                method: 'PATCH',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(
                  node.type === 'directory'
                    ? { oldPath: toFolderPath(node.path), newName }
                    : { newName }
                )
              }
            )
          : await fetch(`/api/v1/files/rename`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                basePath,
                oldPath: node.path,
                newName
              })
            });

        if (!response.ok) throw new Error('Failed to rename');

        const currentStore = get(ctx.editorStore);
        if (currentStore.currentNoteId === node.path) {
          ctx.editorStore.updateNoteName(newName);
        }

        if (basePath === 'notes') {
          if (node.type === 'directory') {
            ctx.treeStore.renameFolderNode?.(toFolderPath(node.path), newName);
          } else {
            ctx.treeStore.renameNoteNode?.(node.path, newName);
          }
        } else {
          ctx.treeStore.renameWorkspaceNode?.(basePath, node.path, newName);
        }
        if (basePath === 'notes') {
          dispatchCacheEvent('note.renamed');
        } else {
          dispatchCacheEvent('file.renamed');
        }
      } catch (error) {
        logError('Failed to rename', error, {
          scope: 'fileActions.rename',
          basePath,
          nodePath: node.path
        });
        ctx.setEditedName(node.name);
      }
    }
    ctx.setIsEditing(false);
  };

  const cancelRename = () => {
    ctx.setEditedName(ctx.getNode().name);
    ctx.setIsEditing(false);
  };

  const openDeleteDialog = () => {
    ctx.requestDelete();
  };

  const handlePinToggle = async () => {
    const node = ctx.getNode();
    if (node.type !== 'file') return;
    try {
      const pinned = !node.pinned;
      const response = await fetch(`/api/v1/notes/${node.path}/pin`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pinned })
      });
      if (!response.ok) throw new Error('Failed to update pin');
      ctx.treeStore.setNotePinned?.(node.path, pinned);
      dispatchCacheEvent('note.pinned');
    } catch (error) {
      logError('Failed to pin note', error, {
        scope: 'fileActions.pin',
        noteId: node.path
      });
    }
  };

  const handleArchive = async () => {
    const node = ctx.getNode();
    if (node.type !== 'file') return;
    try {
      const response = await fetch(`/api/v1/notes/${node.path}/archive`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ archived: true })
      });
      if (!response.ok) throw new Error('Failed to archive note');
      ctx.treeStore.archiveNoteNode?.(node.path, true);
      dispatchCacheEvent('note.archived');
    } catch (error) {
      logError('Failed to archive note', error, {
        scope: 'fileActions.archive',
        noteId: node.path
      });
    }
  };

  const handleUnarchive = async () => {
    const node = ctx.getNode();
    if (node.type !== 'file') return;
    try {
      const response = await fetch(`/api/v1/notes/${node.path}/archive`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ archived: false })
      });
      if (!response.ok) throw new Error('Failed to unarchive note');
      ctx.treeStore.archiveNoteNode?.(node.path, false);
      dispatchCacheEvent('note.archived');
    } catch (error) {
      logError('Failed to unarchive note', error, {
        scope: 'fileActions.unarchive',
        noteId: node.path
      });
    }
  };

  const handleMove = async (folder: string) => {
    const node = ctx.getNode();
    if (node.type !== 'file') return;
    try {
      const response = ctx.getBasePath() === 'notes'
        ? await fetch(`/api/v1/notes/${node.path}/move`, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ folder })
          })
        : await fetch(`/api/v1/files/move`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              basePath: ctx.getBasePath(),
              path: node.path,
              destination: folder
            })
          });
      if (!response.ok) throw new Error('Failed to move file');
      if (ctx.getBasePath() === 'notes') {
        ctx.treeStore.moveNoteNode?.(node.path, folder);
        dispatchCacheEvent('note.moved');
      } else {
        ctx.treeStore.moveWorkspaceNode?.(ctx.getBasePath(), node.path, folder);
        dispatchCacheEvent('file.moved');
      }
    } catch (error) {
      logError('Failed to move file', error, {
        scope: 'fileActions.move',
        basePath: ctx.getBasePath(),
        nodePath: node.path,
        destination: folder
      });
    }
  };

  const handleMoveFolder = async (newParent: string) => {
    const node = ctx.getNode();
    if (node.type !== 'directory') return;
    try {
      const response = ctx.getBasePath() === 'notes'
        ? await fetch('/api/v1/notes/folders/move', {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              oldPath: toFolderPath(node.path),
              newParent
            })
          })
        : await fetch('/api/v1/files/move', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              basePath: ctx.getBasePath(),
              path: node.path,
              destination: newParent
            })
          });
      if (!response.ok) throw new Error('Failed to move folder');
      if (ctx.getBasePath() === 'notes') {
        ctx.treeStore.moveFolderNode?.(toFolderPath(node.path), newParent);
        dispatchCacheEvent('note.moved');
      } else {
        ctx.treeStore.moveWorkspaceNode?.(ctx.getBasePath(), node.path, newParent);
        dispatchCacheEvent('file.moved');
      }
    } catch (error) {
      logError('Failed to move folder', error, {
        scope: 'fileActions.moveFolder',
        basePath: ctx.getBasePath(),
        nodePath: node.path,
        destination: newParent
      });
    }
  };

  const handleDownload = async () => {
    const node = ctx.getNode();
    if (node.type !== 'file') return;
    try {
      const link = document.createElement('a');
      if (ctx.getBasePath() === 'notes') {
        link.href = `/api/v1/notes/${node.path}/download`;
        link.download = `${ctx.getDisplayName()}.md`;
      } else {
        link.href = `/api/v1/files/download?basePath=${encodeURIComponent(ctx.getBasePath())}&path=${encodeURIComponent(node.path)}`;
        link.download = ctx.getDisplayName();
      }
      document.body.appendChild(link);
      link.click();
      link.remove();
    } catch (error) {
      logError('Failed to download file', error, {
        scope: 'fileActions.download',
        basePath: ctx.getBasePath(),
        nodePath: node.path
      });
    }
  };

  const confirmDelete = async (): Promise<boolean> => {
    const node = ctx.getNode();
    try {
      const response = ctx.getBasePath() === 'notes'
        ? await fetch(
            node.type === 'directory'
              ? '/api/v1/notes/folders'
              : `/api/v1/notes/${node.path}`,
            {
              method: 'DELETE',
              headers: { 'Content-Type': 'application/json' },
              body: node.type === 'directory'
                ? JSON.stringify({ path: toFolderPath(node.path) })
                : undefined
            }
          )
        : await fetch(`/api/v1/files/delete`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              basePath: ctx.getBasePath(),
              path: node.path
            })
          });

      if (!response.ok) throw new Error('Failed to delete');

      const currentStore = get(ctx.editorStore);
      if (currentStore.currentNoteId === node.path) {
        ctx.editorStore.reset();
      }

      ctx.treeStore.removeNode(ctx.getBasePath(), node.path);
      if (ctx.getBasePath() === 'notes') {
        dispatchCacheEvent('note.deleted');
      } else {
        dispatchCacheEvent('file.deleted');
      }
      return true;
    } catch (error) {
      logError('Failed to delete', error, {
        scope: 'fileActions.delete',
        basePath: ctx.getBasePath(),
        nodePath: node.path
      });
      return false;
    }
  };

  return {
    buildFolderOptions,
    startRename,
    saveRename,
    cancelRename,
    openDeleteDialog,
    handlePinToggle,
    handleArchive,
    handleUnarchive,
    handleMove,
    handleMoveFolder,
    handleDownload,
    confirmDelete
  };
}
