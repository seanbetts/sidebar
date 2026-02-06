import { browser } from '$app/environment';
import { writable } from 'svelte/store';
import type { SidebarSection } from '$lib/hooks/useSidebarSectionLoader';

const STORAGE_KEY = 'sideBar.lastSelectedSection';
const DEFAULT_SECTION: SidebarSection = 'notes';
const VALID_SECTIONS: SidebarSection[] = ['chat', 'notes', 'websites', 'files', 'tasks'];

function migrateLegacySection(value: string | null): string | null {
	if (value === 'history') return 'chat';
	if (value === 'workspace') return 'files';
	return value;
}

function isSidebarSection(value: unknown): value is SidebarSection {
	return typeof value === 'string' && VALID_SECTIONS.includes(value as SidebarSection);
}

function readStoredSection(): SidebarSection {
	if (!browser) return DEFAULT_SECTION;
	try {
		const stored = migrateLegacySection(localStorage.getItem(STORAGE_KEY));
		return isSidebarSection(stored) ? stored : DEFAULT_SECTION;
	} catch {
		return DEFAULT_SECTION;
	}
}

function createSidebarSectionStore() {
	const { subscribe, set } = writable<SidebarSection>(readStoredSection());

	return {
		subscribe,
		set(section: SidebarSection) {
			if (browser) {
				localStorage.setItem(STORAGE_KEY, section);
			}
			set(section);
		},
		reset() {
			if (browser) {
				localStorage.removeItem(STORAGE_KEY);
			}
			set(DEFAULT_SECTION);
		}
	};
}

export const sidebarSectionStore = createSidebarSectionStore();
