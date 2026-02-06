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
		localStorage.setItem('sideBar.lastSelectedSection', 'chat');
		const { sidebarSectionStore } = await import('$lib/stores/sidebar-section');
		expect(get(sidebarSectionStore)).toBe('chat');
	});

	it('migrates legacy stored sections', async () => {
		localStorage.setItem('sideBar.lastSelectedSection', 'workspace');
		const { sidebarSectionStore } = await import('$lib/stores/sidebar-section');
		expect(get(sidebarSectionStore)).toBe('files');

		localStorage.setItem('sideBar.lastSelectedSection', 'history');
		vi.resetModules();
		const { sidebarSectionStore: reloadedStore } = await import('$lib/stores/sidebar-section');
		expect(get(reloadedStore)).toBe('chat');
	});

	it('persists section changes', async () => {
		const { sidebarSectionStore } = await import('$lib/stores/sidebar-section');
		sidebarSectionStore.set('websites');
		expect(get(sidebarSectionStore)).toBe('websites');
		expect(localStorage.getItem('sideBar.lastSelectedSection')).toBe('websites');
	});
});
