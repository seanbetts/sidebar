import type { FileTreeState } from '$lib/types/file';

export type TreeStoreUpdater = (fn: (state: FileTreeState) => FileTreeState) => void;
export type TreeStoreSetter = (state: FileTreeState) => void;

export type TreeStoreContext = {
	update: TreeStoreUpdater;
	set: TreeStoreSetter;
	getState: () => FileTreeState;
};
