import { writable } from 'svelte/store';
import type { SidebarSection } from '$lib/hooks/useSidebarSectionLoader';

export const sidebarSectionStore = writable<SidebarSection>('notes');
