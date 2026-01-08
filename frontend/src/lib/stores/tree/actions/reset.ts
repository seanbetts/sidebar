import type { TreeStoreContext } from '$lib/stores/tree/types';
import { invalidateCache } from '$lib/utils/cache';
import { getExpandedCacheKey, getTreeCacheKey } from '$lib/stores/tree/cache';

export function createResetAction(context: TreeStoreContext) {
	return () => {
		const currentState = context.getState();
		Object.keys(currentState.trees).forEach((basePath) => {
			invalidateCache(getTreeCacheKey(basePath));
			invalidateCache(getExpandedCacheKey(basePath));
		});
		context.set({ trees: {} });
	};
}
