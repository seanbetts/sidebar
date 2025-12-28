import { get } from 'svelte/store';
import type { Writable } from 'svelte/store';

type NoteNode = { pinned?: boolean } | null;

type EditorActionsContext = {
  editorStore: Writable<any>;
  filesStore: {
    load: (tree: string, force?: boolean) => Promise<void>;
    trees: Record<string, any>;
    removeNode?: (basePath: string, path: string) => void;
    addNoteNode?: (payload: { id: string; name: string; folder?: string; modified?: number }) => void;
  };
  getCurrentNoteId: () => string | null;
  getDisplayTitle: () => string;
  getNoteNode: () => NoteNode;
  getIsDirty: () => boolean;
  getRenameValue: () => string;
  setRenameValue: (value: string) => void;
  setIsSaveBeforeCloseDialogOpen: (value: boolean) => void;
  setIsSaveBeforeRenameDialogOpen: (value: boolean) => void;
  setIsRenameDialogOpen: (value: boolean) => void;
  setIsDeleteDialogOpen: (value: boolean) => void;
  setFolderOptions: (value: { label: string; value: string; depth: number }[]) => void;
  getCopyTimeout: () => ReturnType<typeof setTimeout> | null;
  setCopyTimeout: (value: ReturnType<typeof setTimeout> | null) => void;
  setIsCopied: (value: boolean) => void;
};

/**
 * Build editor-side action handlers for note operations.
 *
 * @param ctx - Context with editor state and UI setters.
 * @returns Action handlers for editor UI interactions.
 */
export function useEditorActions(ctx: EditorActionsContext) {
  const buildFolderOptions = () => {
    const tree = ctx.filesStore.trees['notes'];
    const nodes = tree?.children || [];
    const options: { label: string; value: string; depth: number }[] = [
      { label: 'Notes', value: '', depth: 0 }
    ];

    const walk = (items: any[], depth: number) => {
      for (const item of items) {
        if (item.type !== 'directory') continue;
        if (item.name === 'Archive') continue;
        const folderPath = item.path.replace(/^folder:/, '');
        options.push({ label: item.name, value: folderPath, depth });
        if (item.children?.length) {
          walk(item.children, depth + 1);
        }
      }
    };

    walk(nodes, 1);
    ctx.setFolderOptions(options);
  };

  const handleClose = async () => {
    if (ctx.getIsDirty()) {
      ctx.setIsSaveBeforeCloseDialogOpen(true);
      return;
    }
    ctx.editorStore.reset();
  };

  const confirmSaveAndClose = async () => {
    await ctx.editorStore.saveNote();
    ctx.setIsSaveBeforeCloseDialogOpen(false);
    ctx.editorStore.reset();
  };

  const discardAndClose = () => {
    ctx.setIsSaveBeforeCloseDialogOpen(false);
    ctx.editorStore.reset();
  };

  const openRenameDialog = () => {
    ctx.setRenameValue(ctx.getDisplayTitle());
    if (ctx.getIsDirty()) {
      ctx.setIsSaveBeforeRenameDialogOpen(true);
      return;
    }
    ctx.setIsRenameDialogOpen(true);
  };

  const confirmSaveAndRename = async () => {
    await ctx.editorStore.saveNote();
    ctx.setIsSaveBeforeRenameDialogOpen(false);
    ctx.setIsRenameDialogOpen(true);
  };

  const discardAndRename = () => {
    ctx.setIsSaveBeforeRenameDialogOpen(false);
    ctx.setIsRenameDialogOpen(true);
  };

  const handleRename = async () => {
    const currentNoteId = ctx.getCurrentNoteId();
    if (!currentNoteId) return;
    const trimmed = ctx.getRenameValue().trim();
    if (!trimmed || trimmed === ctx.getDisplayTitle()) {
      ctx.setIsRenameDialogOpen(false);
      return;
    }
    const response = await fetch(`/api/notes/${currentNoteId}/rename`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ newName: `${trimmed}.md` })
    });
    if (!response.ok) {
      console.error('Failed to rename note');
      return;
    }
    await ctx.filesStore.load('notes');
    await ctx.editorStore.loadNote('notes', currentNoteId, { source: 'user' });
    ctx.setIsRenameDialogOpen(false);
  };

  const handleMove = async (folder: string) => {
    const currentNoteId = ctx.getCurrentNoteId();
    if (!currentNoteId) return;
    const response = await fetch(`/api/notes/${currentNoteId}/move`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ folder })
    });
    if (!response.ok) {
      console.error('Failed to move note');
      return;
    }
    await ctx.filesStore.load('notes');
  };

  const handleArchive = async () => {
    const currentNoteId = ctx.getCurrentNoteId();
    if (!currentNoteId) return;
    const response = await fetch(`/api/notes/${currentNoteId}/archive`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ archived: true })
    });
    if (!response.ok) {
      console.error('Failed to archive note');
      return;
    }
    await ctx.filesStore.load('notes');
    ctx.editorStore.reset();
  };

  const handlePinToggle = async () => {
    const currentNoteId = ctx.getCurrentNoteId();
    if (!currentNoteId) return;
    const node = ctx.getNoteNode();
    const pinned = !(node?.pinned);
    const response = await fetch(`/api/notes/${currentNoteId}/pin`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pinned })
    });
    if (!response.ok) {
      console.error('Failed to update pin');
      return;
    }
    await ctx.filesStore.load('notes');
  };

  const handleDownload = async () => {
    const currentNoteId = ctx.getCurrentNoteId();
    if (!currentNoteId) return;
    const link = document.createElement('a');
    link.href = `/api/notes/${currentNoteId}/download`;
    link.download = `${ctx.getDisplayTitle() || 'note'}.md`;
    document.body.appendChild(link);
    link.click();
    link.remove();
  };

  const handleCopy = async () => {
    const currentNoteId = ctx.getCurrentNoteId();
    if (!currentNoteId) return;
    try {
      const content = get(ctx.editorStore).content || '';
      await navigator.clipboard.writeText(content);
      ctx.setIsCopied(true);
      const timeout = ctx.getCopyTimeout();
      if (timeout) clearTimeout(timeout);
      ctx.setCopyTimeout(
        setTimeout(() => {
          ctx.setIsCopied(false);
          ctx.setCopyTimeout(null);
        }, 1500)
      );
    } catch (error) {
      console.error('Failed to copy note content:', error);
    }
  };

  const handleDelete = async () => {
    const currentNoteId = ctx.getCurrentNoteId();
    if (!currentNoteId) return;
    const response = await fetch(`/api/notes/${currentNoteId}`, {
      method: 'DELETE'
    });
    if (!response.ok) {
      console.error('Failed to delete note');
      return;
    }
    ctx.filesStore.removeNode?.('notes', currentNoteId);
    await ctx.filesStore.load('notes', true);
    ctx.editorStore.reset();
    ctx.setIsDeleteDialogOpen(false);
  };

  return {
    buildFolderOptions,
    handleArchive,
    handleClose,
    handleCopy,
    handleDelete,
    handleDownload,
    handleMove,
    handlePinToggle,
    handleRename,
    openRenameDialog,
    confirmSaveAndClose,
    confirmSaveAndRename,
    discardAndClose,
    discardAndRename
  };
}
