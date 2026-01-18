import { writable } from 'svelte/store';

function createFilesSearchStore() {
	const { subscribe, set } = writable('');

	return {
		subscribe,
		set,
		clear: () => set('')
	};
}

export const filesSearchStore = createFilesSearchStore();
