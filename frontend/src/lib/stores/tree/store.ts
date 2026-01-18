/**
 * Tree store for managing notes file tree.
 */
import { writable, get } from 'svelte/store';
import type { FileTreeState } from '$lib/types/file';
import type { TreeStoreContext } from '$lib/stores/tree/types';
import { createLoadActions } from '$lib/stores/tree/actions/load';
import { createMutationActions } from '$lib/stores/tree/actions/mutations';
import { createNotesActions } from '$lib/stores/tree/actions/notes';
import { createSearchActions } from '$lib/stores/tree/actions/search';
import { createResetAction } from '$lib/stores/tree/actions/reset';

export function createTreeStore() {
	const { subscribe, set, update } = writable<FileTreeState>({
		trees: {}
	});

	const context: TreeStoreContext = {
		update,
		set,
		getState: () => get({ subscribe })
	};

	const loadActions = createLoadActions(context);
	const mutationActions = createMutationActions(context);
	const notesActions = createNotesActions(context);
	const searchActions = createSearchActions(context);
	const reset = createResetAction(context);

	return {
		subscribe,
		...loadActions,
		...mutationActions,
		...notesActions,
		...searchActions,
		reset
	};
}

export const treeStore = createTreeStore();
export type TreeStore = ReturnType<typeof createTreeStore>;
