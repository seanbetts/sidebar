import { describe, expect, it } from 'vitest';
import { get } from 'svelte/store';
import { sidebarSectionStore } from '$lib/stores/sidebar-section';

describe('sidebarSectionStore', () => {
  it('defaults to notes section', () => {
    expect(get(sidebarSectionStore)).toBe('notes');
  });
});
