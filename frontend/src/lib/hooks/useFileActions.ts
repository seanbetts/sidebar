import { get } from 'svelte/store';
import type { FileNode } from '$lib/types/file';
import type { EditorStore } from '$lib/stores/editor';
import type { TreeStore } from '$lib/stores/tree/store';
import { dispatchCacheEvent } from '$lib/utils/cacheEvents';
import { logError } from '$lib/utils/errorHandling';
import { toast } from 'svelte-sonner';

const NOTE_ARCHIVE_NAME = 'Archive';

type FileActionsContext = {
	getNode: () => FileNode;
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
		const tree = get(ctx.treeStore).trees.notes;
		const rootChildren = tree?.children || [];
		const options: { label: string; value: string; depth: number }[] = [
			{ label: 'Notes', value: '', depth: 0 }
		];

		const walk = (nodes: FileNode[], depth: number) => {
			for (const child of nodes) {
				if (child.type !== 'directory') continue;
				if (child.name === NOTE_ARCHIVE_NAME) continue;
				const folderPath = toFolderPath(child.path);
				if (
					excludePath &&
					(folderPath === excludePath || folderPath.startsWith(`${excludePath}/`))
				) {
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

				const response = await fetch(
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
				);

				if (!response.ok) throw new Error('Failed to rename');

				const currentStore = get(ctx.editorStore);
				if (currentStore.currentNoteId === node.path) {
					ctx.editorStore.updateNoteName(newName);
				}

				if (node.type === 'directory') {
					ctx.treeStore.renameFolderNode?.(toFolderPath(node.path), newName);
				} else {
					ctx.treeStore.renameNoteNode?.(node.path, newName);
				}
				dispatchCacheEvent('note.renamed');
			} catch (error) {
				toast.error('Failed to rename');
				logError('Failed to rename', error, {
					scope: 'fileActions.rename',
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
			toast.error('Failed to pin note');
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
			toast.error('Failed to archive note');
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
			toast.error('Failed to unarchive note');
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
			const response = await fetch(`/api/v1/notes/${node.path}/move`, {
				method: 'PATCH',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ folder })
			});
			if (!response.ok) throw new Error('Failed to move note');
			ctx.treeStore.moveNoteNode?.(node.path, folder);
			dispatchCacheEvent('note.moved');
		} catch (error) {
			toast.error('Failed to move note');
			logError('Failed to move file', error, {
				scope: 'fileActions.move',
				nodePath: node.path,
				destination: folder
			});
		}
	};

	const handleMoveFolder = async (newParent: string) => {
		const node = ctx.getNode();
		if (node.type !== 'directory') return;
		try {
			const response = await fetch('/api/v1/notes/folders/move', {
				method: 'PATCH',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					oldPath: toFolderPath(node.path),
					newParent
				})
			});
			if (!response.ok) throw new Error('Failed to move folder');
			ctx.treeStore.moveFolderNode?.(toFolderPath(node.path), newParent);
			dispatchCacheEvent('note.moved');
		} catch (error) {
			toast.error('Failed to move folder');
			logError('Failed to move folder', error, {
				scope: 'fileActions.moveFolder',
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
			link.href = `/api/v1/notes/${node.path}/download`;
			link.download = `${ctx.getDisplayName()}.md`;
			document.body.appendChild(link);
			link.click();
			link.remove();
		} catch (error) {
			logError('Failed to download file', error, {
				scope: 'fileActions.download',
				nodePath: node.path
			});
		}
	};

	const confirmDelete = async (): Promise<boolean> => {
		const node = ctx.getNode();
		try {
			const response = await fetch(
				node.type === 'directory' ? '/api/v1/notes/folders' : `/api/v1/notes/${node.path}`,
				{
					method: 'DELETE',
					headers: { 'Content-Type': 'application/json' },
					body:
						node.type === 'directory'
							? JSON.stringify({ path: toFolderPath(node.path) })
							: undefined
				}
			);

			if (!response.ok) throw new Error('Failed to delete');

			const currentStore = get(ctx.editorStore);
			if (currentStore.currentNoteId === node.path) {
				ctx.editorStore.reset();
			}

			ctx.treeStore.removeNode('notes', node.path);
			dispatchCacheEvent('note.deleted');
			return true;
		} catch (error) {
			toast.error('Failed to delete');
			logError('Failed to delete', error, {
				scope: 'fileActions.delete',
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
