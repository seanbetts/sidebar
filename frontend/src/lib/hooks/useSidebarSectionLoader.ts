import { get } from 'svelte/store';
import { conversationListStore } from '$lib/stores/conversations';
import { treeStore } from '$lib/stores/tree';
import { websitesStore } from '$lib/stores/websites';
import { ingestionStore } from '$lib/stores/ingestion';
import { tasksStore } from '$lib/stores/tasks';

export type SidebarSection = 'chat' | 'notes' | 'websites' | 'files' | 'tasks';

/**
 * Lazily load sidebar section data on first open.
 *
 * @returns Loader for section data.
 */
export function useSidebarSectionLoader() {
	const loadSectionData = (section: SidebarSection) => {
		const treeState = get(treeStore);
		const websitesState = get(websitesStore);
		const conversationsState = get(conversationListStore);
		const ingestionState = get(ingestionStore);

		const hasData = {
			notes: treeState.trees?.['notes']?.loaded ?? false,
			websites: websitesState.loaded ?? false,
			files: ingestionState.loaded ?? false,
			chat: conversationsState.loaded ?? false,
			tasks: false
		}[section];

		if (hasData) {
			return;
		}

		switch (section) {
			case 'notes':
				treeStore.load('notes');
				break;
			case 'websites':
				websitesStore.load();
				break;
			case 'files':
				ingestionStore.load();
				break;
			case 'chat':
				conversationListStore.load();
				break;
			case 'tasks':
				tasksStore.load({ type: 'today' });
				break;
		}
	};

	return { loadSectionData };
}
