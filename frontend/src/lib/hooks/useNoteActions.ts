import { get } from 'svelte/store';
import { notesAPI } from '$lib/services/api';
import { treeStore } from '$lib/stores/tree';
import { logError } from '$lib/utils/errorHandling';
import { toast } from 'svelte-sonner';
import type { FileNode } from '$lib/types/file';

type NotesActionOptions = {
	scope?: string;
};

const defaultScope = (action: string) => `notesActions.${action}`;

function collectPinnedOrder(nodes: FileNode[]): string[] {
	const pinned: { path: string; order: number }[] = [];
	const walk = (items: FileNode[]) => {
		for (const item of items) {
			if (item.type === 'file' && item.pinned) {
				pinned.push({ path: item.path, order: item.pinned_order ?? Infinity });
			}
			if (item.children) walk(item.children);
		}
	};
	walk(nodes);
	pinned.sort((a, b) => a.order - b.order);
	return pinned.map((p) => p.path);
}

/**
 * Provide reusable notes action handlers for pinned ordering.
 *
 * @returns Notes action handlers.
 */
export function useNoteActions() {
	const updatePinnedOrder = async (
		order: string[],
		options: NotesActionOptions = {}
	): Promise<boolean> => {
		const tree = get(treeStore).trees['notes'];
		const previousOrder = tree?.children ? collectPinnedOrder(tree.children) : [];
		treeStore.setNotePinnedOrder(order);
		try {
			await notesAPI.updatePinnedOrder(order);
			return true;
		} catch (error) {
			treeStore.setNotePinnedOrder(previousOrder);
			toast.error('Failed to reorder pinned notes');
			logError('Failed to update pinned order', error, {
				scope: options.scope ?? defaultScope('pinnedOrder')
			});
			return false;
		}
	};

	return {
		updatePinnedOrder
	};
}
