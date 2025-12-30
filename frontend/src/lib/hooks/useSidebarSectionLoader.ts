import { get } from 'svelte/store';
import { conversationListStore } from '$lib/stores/conversations';
import { treeStore } from '$lib/stores/tree';
import { websitesStore } from '$lib/stores/websites';

export type SidebarSection = 'history' | 'notes' | 'websites' | 'workspace';

/**
 * Lazily load sidebar section data on first open.
 *
 * @returns Loader for section data.
 */
export function useSidebarSectionLoader() {
	const loadedSections = new Set<SidebarSection>();

	const loadSectionData = (section: SidebarSection) => {
		if (loadedSections.has(section)) {
			return;
		}

		const treeState = get(treeStore);
		const websitesState = get(websitesStore);
		const conversationsState = get(conversationListStore);

		const hasData = {
			notes: treeState.trees?.['notes']?.loaded ?? false,
			websites: websitesState.loaded ?? false,
			workspace: treeState.trees?.['.']?.loaded ?? false,
			history: conversationsState.loaded ?? false
		}[section];

		if (hasData) {
			loadedSections.add(section);
			return;
		}

		loadedSections.add(section);

		switch (section) {
			case 'notes':
				treeStore.load('notes');
				break;
			case 'websites':
				websitesStore.load();
				break;
			case 'workspace':
				treeStore.load('.');
				break;
			case 'history':
				conversationListStore.load();
				break;
		}
	};

	return { loadSectionData };
}
