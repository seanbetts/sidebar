import { beforeEach, describe, expect, it, vi } from 'vitest';
import { get } from 'svelte/store';

vi.mock('$app/environment', () => ({ browser: true }));

function setStoredLayout(value: unknown) {
  localStorage.setItem('sideBar.layout', JSON.stringify(value));
}

describe('layoutStore', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.resetModules();
  });

  it('hydrates legacy ratio fields', async () => {
    setStoredLayout({ chatPanelRatio: 0.25 });
    const { layoutStore } = await import('$lib/stores/layout');

    expect(get(layoutStore).sidebarRatio).toBe(0.25);
  });

  it('clamps sidebar ratio', async () => {
    const { layoutStore } = await import('$lib/stores/layout');

    layoutStore.setSidebarRatio(0.1);
    expect(get(layoutStore).sidebarRatio).toBe(0.2);

    layoutStore.setSidebarRatio(0.6);
    expect(get(layoutStore).sidebarRatio).toBe(0.5);
  });
});
