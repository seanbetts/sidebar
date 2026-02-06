import { beforeEach, describe, expect, it, vi } from 'vitest';
import { get } from 'svelte/store';

vi.mock('$app/environment', () => ({ browser: true }));

describe('sidebarSectionStore', () => {
	beforeEach(() => {
		localStorage.clear();
		vi.resetModules();
	});

	it('defaults to notes section', async () => {
		const { sidebarSectionStore } = await import('$lib/stores/sidebar-section');
		expect(get(sidebarSectionStore)).toBe('notes');
	});

	it('hydrates stored section', async () => {
		localStorage.setItem('sideBar.lastSelectedSection', 'history');
		const { sidebarSectionStore } = await import('$lib/stores/sidebar-section');
		expect(get(sidebarSectionStore)).toBe('history');
	});

	it('persists section changes', async () => {
		const { sidebarSectionStore } = await import('$lib/stores/sidebar-section');
		sidebarSectionStore.set('websites');
		expect(get(sidebarSectionStore)).toBe('websites');
		expect(localStorage.getItem('sideBar.lastSelectedSection')).toBe('websites');
	});
});
