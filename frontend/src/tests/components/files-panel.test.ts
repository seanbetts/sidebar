import { render, screen } from '@testing-library/svelte';
import { describe, expect, it, vi } from 'vitest';
import FilesPanel from '$lib/components/left-sidebar/FilesPanel.svelte';

vi.mock('$lib/stores/tree', () => ({
  treeStore: (() => {
    const { writable } = require('svelte/store');
    const treeState = writable({
      trees: {
        documents: {
          children: [],
          loading: false,
          searchQuery: ''
        }
      }
    });
    return { subscribe: treeState.subscribe };
  })()
}));

vi.mock('$lib/stores/ingestion', () => ({
  ingestionStore: (() => {
    const { writable } = require('svelte/store');
    const ingestionState = writable({
      items: [],
      localUploads: [],
      loading: false
    });
    return {
      subscribe: ingestionState.subscribe,
      startPolling: vi.fn(),
      stopPolling: vi.fn()
    };
  })()
}));

vi.mock('$lib/stores/ingestion-viewer', () => ({
  ingestionViewerStore: (() => {
    const { writable } = require('svelte/store');
    const ingestionViewerState = writable({ active: null });
    return {
      subscribe: ingestionViewerState.subscribe,
      open: vi.fn(),
      clearActive: vi.fn(),
      updatePinned: vi.fn(),
      updateFilename: vi.fn(),
      setLocalActive: vi.fn(),
      updateActiveJob: vi.fn()
    };
  })()
}));

vi.mock('$lib/stores/websites', () => ({
  websitesStore: {
    clearActive: vi.fn()
  }
}));

vi.mock('$lib/stores/editor', () => ({
  editorStore: {
    reset: vi.fn()
  },
  currentNoteId: (() => {
    const { writable } = require('svelte/store');
    return writable<string | null>(null);
  })()
}));

vi.mock('$lib/services/api', () => ({
  ingestionAPI: {
    delete: vi.fn(),
    setPinned: vi.fn(),
    updatePinnedOrder: vi.fn(),
    rename: vi.fn(),
    getContent: vi.fn()
  }
}));

vi.mock('$lib/utils/cacheEvents', () => ({
  dispatchCacheEvent: vi.fn()
}));

describe('FilesPanel', () => {
  it('shows empty state when no files are available', () => {
    render(FilesPanel);
    expect(screen.getByText('No files yet')).toBeInTheDocument();
  });
});
