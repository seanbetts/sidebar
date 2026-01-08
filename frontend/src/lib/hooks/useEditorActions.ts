import { get } from 'svelte/store';
import type { EditorStore } from '$lib/stores/editor';
import type { TreeStore } from '$lib/stores/tree/store';
import { dispatchCacheEvent } from '$lib/utils/cacheEvents';
import { logError } from '$lib/utils/errorHandling';
import { toast } from 'svelte-sonner';

type NoteNode = { pinned?: boolean; archived?: boolean } | null;

type EditorActionsContext = {
	editorStore: EditorStore;
	treeStore: TreeStore;
	getCurrentNoteId: () => string | null;
	getDisplayTitle: () => string;
	getNoteNode: () => NoteNode;
	getIsDirty: () => boolean;
	getRenameValue: () => string;
	setRenameValue: (value: string) => void;
	setIsSaveBeforeCloseDialogOpen: (value: boolean) => void;
	setIsSaveBeforeRenameDialogOpen: (value: boolean) => void;
	setIsRenameDialogOpen: (value: boolean) => void;
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
		const tree = get(ctx.treeStore).trees?.['notes'];
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
		const response = await fetch(`/api/v1/notes/${currentNoteId}/rename`, {
			method: 'PATCH',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ newName: `${trimmed}.md` })
		});
		if (!response.ok) {
			toast.error('Failed to rename note');
			logError('Failed to rename note', new Error('Request failed'), {
				scope: 'editorActions.rename',
				noteId: currentNoteId,
				status: response.status
			});
			return;
		}
		const nextName = `${trimmed}.md`;
		ctx.treeStore.renameNoteNode?.(currentNoteId, nextName);
		ctx.editorStore.updateNoteName(nextName);
		dispatchCacheEvent('note.renamed');
		ctx.setIsRenameDialogOpen(false);
	};

	const handleMove = async (folder: string) => {
		const currentNoteId = ctx.getCurrentNoteId();
		if (!currentNoteId) return;
		const response = await fetch(`/api/v1/notes/${currentNoteId}/move`, {
			method: 'PATCH',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ folder })
		});
		if (!response.ok) {
			toast.error('Failed to move note');
			logError('Failed to move note', new Error('Request failed'), {
				scope: 'editorActions.move',
				noteId: currentNoteId,
				status: response.status
			});
			return;
		}
		ctx.treeStore.moveNoteNode?.(currentNoteId, folder);
		dispatchCacheEvent('note.moved');
	};

	const handleArchive = async () => {
		const currentNoteId = ctx.getCurrentNoteId();
		if (!currentNoteId) return;
		const response = await fetch(`/api/v1/notes/${currentNoteId}/archive`, {
			method: 'PATCH',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ archived: true })
		});
		if (!response.ok) {
			toast.error('Failed to archive note');
			logError('Failed to archive note', new Error('Request failed'), {
				scope: 'editorActions.archive',
				noteId: currentNoteId,
				status: response.status
			});
			return;
		}
		ctx.treeStore.archiveNoteNode?.(currentNoteId, true);
		ctx.editorStore.reset();
		dispatchCacheEvent('note.archived');
	};

	const handleUnarchive = async () => {
		const currentNoteId = ctx.getCurrentNoteId();
		if (!currentNoteId) return;
		const response = await fetch(`/api/v1/notes/${currentNoteId}/archive`, {
			method: 'PATCH',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ archived: false })
		});
		if (!response.ok) {
			toast.error('Failed to unarchive note');
			logError('Failed to unarchive note', new Error('Request failed'), {
				scope: 'editorActions.unarchive',
				noteId: currentNoteId,
				status: response.status
			});
			return;
		}
		ctx.treeStore.archiveNoteNode?.(currentNoteId, false);
		dispatchCacheEvent('note.archived');
	};

	const handlePinToggle = async () => {
		const currentNoteId = ctx.getCurrentNoteId();
		if (!currentNoteId) return;
		const node = ctx.getNoteNode();
		const pinned = !node?.pinned;
		const response = await fetch(`/api/v1/notes/${currentNoteId}/pin`, {
			method: 'PATCH',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ pinned })
		});
		if (!response.ok) {
			toast.error('Failed to pin note');
			logError('Failed to update pin', new Error('Request failed'), {
				scope: 'editorActions.pin',
				noteId: currentNoteId,
				status: response.status
			});
			return;
		}
		ctx.treeStore.setNotePinned?.(currentNoteId, pinned);
		dispatchCacheEvent('note.pinned');
	};

	const handleDownload = async () => {
		const currentNoteId = ctx.getCurrentNoteId();
		if (!currentNoteId) return;
		const link = document.createElement('a');
		link.href = `/api/v1/notes/${currentNoteId}/download`;
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
			logError('Failed to copy note content', error, {
				scope: 'editorActions.copy',
				noteId: currentNoteId
			});
		}
	};

	const handleDelete = async (): Promise<boolean> => {
		const currentNoteId = ctx.getCurrentNoteId();
		if (!currentNoteId) return false;
		const response = await fetch(`/api/v1/notes/${currentNoteId}`, {
			method: 'DELETE'
		});
		if (!response.ok) {
			toast.error('Failed to delete note');
			logError('Failed to delete note', new Error('Request failed'), {
				scope: 'editorActions.delete',
				noteId: currentNoteId,
				status: response.status
			});
			return false;
		}
		ctx.treeStore.removeNode?.('notes', currentNoteId);
		dispatchCacheEvent('note.deleted');
		ctx.editorStore.reset();
		return true;
	};

	return {
		buildFolderOptions,
		handleArchive,
		handleUnarchive,
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
