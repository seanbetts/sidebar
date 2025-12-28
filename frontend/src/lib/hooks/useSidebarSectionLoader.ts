import { get } from 'svelte/store';
import { conversationListStore } from '$lib/stores/conversations';
import { filesStore } from '$lib/stores/files';
import { websitesStore } from '$lib/stores/websites';

export type SidebarSection = 'history' | 'notes' | 'websites' | 'workspace';

export function useSidebarSectionLoader() {
	const loadedSections = new Set<SidebarSection>();

	const loadSectionData = (section: SidebarSection) => {
		if (loadedSections.has(section)) {
			return;
		}

		const filesState = get(filesStore);
		const websitesState = get(websitesStore);
		const conversationsState = get(conversationListStore);

		const hasData = {
			notes: filesState.trees?.['notes']?.loaded ?? false,
			websites: websitesState.loaded ?? false,
			workspace: filesState.trees?.['.']?.loaded ?? false,
			history: conversationsState.loaded ?? false
		}[section];

		if (hasData) {
			loadedSections.add(section);
			return;
		}

		loadedSections.add(section);

		switch (section) {
			case 'notes':
				filesStore.load('notes');
				break;
			case 'websites':
				websitesStore.load();
				break;
			case 'workspace':
				filesStore.load('.');
				break;
			case 'history':
				conversationListStore.load();
				break;
		}
	};

	return { loadSectionData };
}
