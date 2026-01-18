import type { TreeStoreContext } from '$lib/stores/tree/types';
import { notesAPI } from '$lib/services/api';
import { logError } from '$lib/utils/errorHandling';

export function createSearchActions(context: TreeStoreContext) {
	const searchNotes = async (query: string) => {
		context.update((state) => ({
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
			const children = query ? await notesAPI.search(query) : (await notesAPI.listTree()).children;
			context.update((state) => ({
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
			logError('Failed to search notes', error, { query });
			context.update((state) => ({
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
	};

	return { searchNotes };
}
