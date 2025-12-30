import { get } from 'svelte/store';
import type { FileNode } from '$lib/types/file';
import type { Writable } from 'svelte/store';
import { dispatchCacheEvent } from '$lib/utils/cacheEvents';

const NOTE_ARCHIVE_NAME = 'Archive';

type FileActionsContext = {
  getNode: () => FileNode;
  getBasePath: () => string;
  getHideExtensions: () => boolean;
  getEditedName: () => string;
  setEditedName: (value: string) => void;
  setIsEditing: (value: boolean) => void;
  setIsDeleteDialogOpen: (value: boolean) => void;
  setFolderOptions: (value: { label: string; value: string; depth: number }[]) => void;
  getDisplayName: () => string;
  editorStore: Writable<any>;
  filesStore: Writable<any> & {
    load: (tree: string, force?: boolean) => Promise<void>;
    removeNode: (tree: string, path: string) => void;
    renameNoteNode?: (noteId: string, newName: string) => void;
    setNotePinned?: (noteId: string, pinned: boolean) => void;
    moveNoteNode?: (noteId: string, folder: string, options?: { archived?: boolean }) => void;
    archiveNoteNode?: (noteId: string, archived: boolean) => void;
    renameFolderNode?: (oldPath: string, newName: string) => void;
    moveFolderNode?: (oldPath: string, newParent: string) => void;
  };
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
    const tree = get(ctx.filesStore).trees[basePath];
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
                ? '/api/notes/folders/rename'
                : `/api/notes/${node.path}/rename`,
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
          : await fetch(`/api/files/rename`, {
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
            ctx.filesStore.renameFolderNode?.(toFolderPath(node.path), newName);
          } else {
            ctx.filesStore.renameNoteNode?.(node.path, newName);
          }
        } else {
          await ctx.filesStore.load(basePath, true);
        }
        if (basePath === 'notes') {
          dispatchCacheEvent('note.renamed');
        } else {
          dispatchCacheEvent('file.renamed');
        }
      } catch (error) {
        console.error('Failed to rename:', error);
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
    ctx.setIsDeleteDialogOpen(true);
  };

  const handlePinToggle = async () => {
    const node = ctx.getNode();
    if (node.type !== 'file') return;
    try {
      const pinned = !node.pinned;
      const response = await fetch(`/api/notes/${node.path}/pin`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pinned })
      });
      if (!response.ok) throw new Error('Failed to update pin');
      ctx.filesStore.setNotePinned?.(node.path, pinned);
      dispatchCacheEvent('note.pinned');
    } catch (error) {
      console.error('Failed to pin note:', error);
    }
  };

  const handleArchive = async () => {
    const node = ctx.getNode();
    if (node.type !== 'file') return;
    try {
      const response = await fetch(`/api/notes/${node.path}/archive`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ archived: true })
      });
      if (!response.ok) throw new Error('Failed to archive note');
      ctx.filesStore.archiveNoteNode?.(node.path, true);
      dispatchCacheEvent('note.archived');
    } catch (error) {
      console.error('Failed to archive note:', error);
    }
  };

  const handleMove = async (folder: string) => {
    const node = ctx.getNode();
    if (node.type !== 'file') return;
    try {
      const response = ctx.getBasePath() === 'notes'
        ? await fetch(`/api/notes/${node.path}/move`, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ folder })
          })
        : await fetch(`/api/files/move`, {
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
        ctx.filesStore.moveNoteNode?.(node.path, folder);
        dispatchCacheEvent('note.moved');
      } else {
        await ctx.filesStore.load(ctx.getBasePath(), true);
        dispatchCacheEvent('file.moved');
      }
    } catch (error) {
      console.error('Failed to move file:', error);
    }
  };

  const handleMoveFolder = async (newParent: string) => {
    const node = ctx.getNode();
    if (node.type !== 'directory') return;
    try {
      const response = ctx.getBasePath() === 'notes'
        ? await fetch('/api/notes/folders/move', {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              oldPath: toFolderPath(node.path),
              newParent
            })
          })
        : await fetch('/api/files/move', {
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
        ctx.filesStore.moveFolderNode?.(toFolderPath(node.path), newParent);
        dispatchCacheEvent('note.moved');
      } else {
        await ctx.filesStore.load(ctx.getBasePath(), true);
        dispatchCacheEvent('file.moved');
      }
    } catch (error) {
      console.error('Failed to move folder:', error);
    }
  };

  const handleDownload = async () => {
    const node = ctx.getNode();
    if (node.type !== 'file') return;
    try {
      const link = document.createElement('a');
      if (ctx.getBasePath() === 'notes') {
        link.href = `/api/notes/${node.path}/download`;
        link.download = `${ctx.getDisplayName()}.md`;
      } else {
        link.href = `/api/files/download?basePath=${encodeURIComponent(ctx.getBasePath())}&path=${encodeURIComponent(node.path)}`;
        link.download = ctx.getDisplayName();
      }
      document.body.appendChild(link);
      link.click();
      link.remove();
    } catch (error) {
      console.error('Failed to download note:', error);
    }
  };

  const confirmDelete = async () => {
    const node = ctx.getNode();
    try {
      const response = ctx.getBasePath() === 'notes'
        ? await fetch(
            node.type === 'directory'
              ? '/api/notes/folders'
              : `/api/notes/${node.path}`,
            {
              method: 'DELETE',
              headers: { 'Content-Type': 'application/json' },
              body: node.type === 'directory'
                ? JSON.stringify({ path: toFolderPath(node.path) })
                : undefined
            }
          )
        : await fetch(`/api/files/delete`, {
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

      ctx.filesStore.removeNode(ctx.getBasePath(), node.path);
      if (ctx.getBasePath() !== 'notes') {
        await ctx.filesStore.load(ctx.getBasePath(), true);
      }
      if (ctx.getBasePath() === 'notes') {
        dispatchCacheEvent('note.deleted');
      } else {
        dispatchCacheEvent('file.deleted');
      }
      ctx.setIsDeleteDialogOpen(false);
    } catch (error) {
      console.error('Failed to delete:', error);
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
    handleMove,
    handleMoveFolder,
    handleDownload,
    confirmDelete
  };
}
