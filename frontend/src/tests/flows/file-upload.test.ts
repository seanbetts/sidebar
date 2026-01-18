import { render, fireEvent } from '@testing-library/svelte';
import { describe, expect, it, vi } from 'vitest';
import SidebarWithProviders from '../fixtures/SidebarWithProviders.svelte';

const { createStubComponent } = vi.hoisted(() => ({
	createStubComponent:
		(testId: string) =>
		({ target }: { target: HTMLElement }) => {
			if (target) {
				const el = document.createElement('div');
				el.dataset.testid = testId;
				target.appendChild(el);
			}
			return {
				$set() {},
				$destroy() {}
			};
		}
}));

const {
	ingestionAPI,
	ingestionStore,
	ingestionViewerStore,
	editorStore,
	websitesStore,
	treeStore,
	filesSearchStore,
	thingsStore,
	chatStore,
	conversationListStore,
	currentNoteId,
	sidebarSectionStore
} = vi.hoisted(() => {
	const createStore = <T>(initial: T) => {
		let value = initial;
		const subscribers = new Set<(next: T) => void>();
		return {
			subscribe(run: (next: T) => void) {
				run(value);
				subscribers.add(run);
				return () => subscribers.delete(run);
			},
			set(next: T) {
				value = next;
				subscribers.forEach((fn) => fn(value));
			},
			update(updater: (current: T) => T) {
				value = updater(value);
				subscribers.forEach((fn) => fn(value));
			}
		};
	};
	const ingestionState = createStore({ items: [] as Array<{ file: { id: string } }> });
	return {
		ingestionAPI: {
			upload: vi.fn(),
			get: vi.fn(),
			ingestYoutube: vi.fn()
		},
		ingestionStore: {
			subscribe: ingestionState.subscribe,
			addLocalUpload: vi.fn(() => ({
				id: 'local',
				job: { status: 'uploading' },
				file: { id: 'local' }
			})),
			updateLocalUploadProgress: vi.fn(),
			removeLocalUpload: vi.fn(),
			upsertItem: vi.fn(),
			addLocalSource: vi.fn(),
			startPolling: vi.fn()
		},
		ingestionViewerStore: {
			setLocalActive: vi.fn(),
			updateActiveJob: vi.fn(),
			clearActive: vi.fn(),
			open: vi.fn()
		},
		editorStore: {
			subscribe: createStore({ isDirty: false, currentNoteId: null }).subscribe,
			reset: vi.fn(),
			saveNote: vi.fn(),
			loadNote: vi.fn()
		},
		websitesStore: {
			clearActive: vi.fn(),
			loadById: vi.fn(),
			search: vi.fn(),
			load: vi.fn()
		},
		treeStore: {
			searchNotes: vi.fn(),
			load: vi.fn(),
			addNoteNode: vi.fn(),
			addFolderNode: vi.fn()
		},
		filesSearchStore: {
			set: vi.fn(),
			clear: vi.fn()
		},
		thingsStore: {
			search: vi.fn(),
			clearSearch: vi.fn(),
			startNewTask: vi.fn()
		},
		chatStore: {
			subscribe: createStore({ conversationId: null, messages: [] }).subscribe
		},
		conversationListStore: {
			subscribe: createStore({ conversations: [] as Array<{ id: string; messageCount: number }> })
				.subscribe,
			search: vi.fn(),
			load: vi.fn()
		},
		currentNoteId: createStore<string | null>(null),
		sidebarSectionStore: {
			set: vi.fn()
		}
	};
});

vi.mock('$lib/services/api', () => ({
	ingestionAPI
}));

vi.mock('$lib/stores/ingestion', () => ({
	ingestionStore
}));

vi.mock('$lib/stores/ingestion-viewer', () => ({
	ingestionViewerStore
}));

vi.mock('$lib/stores/editor', () => ({
	editorStore,
	currentNoteId
}));

vi.mock('$lib/stores/websites', () => ({
	websitesStore
}));

vi.mock('$lib/stores/tree', () => ({
	treeStore
}));

vi.mock('$lib/stores/files-search', () => ({
	filesSearchStore
}));

vi.mock('$lib/stores/things', () => ({
	thingsStore
}));

vi.mock('$lib/stores/chat', () => ({
	chatStore
}));

vi.mock('$lib/stores/conversations', () => ({
	conversationListStore
}));

vi.mock('$lib/stores/sidebar-section', () => ({
	sidebarSectionStore
}));

vi.mock('$lib/utils/cacheEvents', () => ({
	dispatchCacheEvent: vi.fn()
}));

vi.mock('$lib/hooks/useSidebarSectionLoader', () => ({
	useSidebarSectionLoader: () => ({
		loadSectionData: vi.fn()
	})
}));

vi.mock('$lib/components/left-sidebar/ConversationList.svelte', () => ({
	default: createStubComponent('conversation-list')
}));

vi.mock('$lib/components/left-sidebar/NotesPanel.svelte', () => ({
	default: createStubComponent('notes-panel')
}));

vi.mock('$lib/components/left-sidebar/FilesPanel.svelte', () => ({
	default: createStubComponent('files-panel')
}));

vi.mock('$lib/components/websites/WebsitesPanel.svelte', () => ({
	default: createStubComponent('websites-panel')
}));

vi.mock('$lib/components/left-sidebar/ThingsPanel.svelte', () => ({
	default: createStubComponent('things-panel')
}));

vi.mock('$lib/components/left-sidebar/SidebarRail.svelte', () => ({
	default: createStubComponent('sidebar-rail')
}));

vi.mock('$lib/components/left-sidebar/panels/SettingsDialogContainer.svelte', () => ({
	default: createStubComponent('settings-dialog')
}));

vi.mock('$lib/components/left-sidebar/dialogs/NewNoteDialog.svelte', () => ({
	default: createStubComponent('new-note-dialog')
}));

vi.mock('$lib/components/left-sidebar/dialogs/NewFolderDialog.svelte', () => ({
	default: createStubComponent('new-folder-dialog')
}));

vi.mock('$lib/components/left-sidebar/dialogs/NewWebsiteDialog.svelte', () => ({
	default: createStubComponent('new-website-dialog')
}));

vi.mock('$lib/components/left-sidebar/dialogs/SaveChangesDialog.svelte', () => ({
	default: createStubComponent('save-changes-dialog')
}));

vi.mock('$lib/components/left-sidebar/dialogs/SidebarErrorDialog.svelte', () => ({
	default: createStubComponent('sidebar-error-dialog')
}));

vi.mock('$lib/components/left-sidebar/dialogs/TextInputDialog.svelte', () => ({
	default: createStubComponent('text-input-dialog')
}));

describe('file upload flow', () => {
	it('uploads a file and requests metadata', async () => {
		ingestionAPI.upload.mockImplementation(
			async (_file: File, onProgress?: (p: number) => void) => {
				onProgress?.(50);
				return { file_id: 'file-123' };
			}
		);
		ingestionAPI.get.mockResolvedValue({
			file: {
				id: 'file-123',
				filename_original: 'test.txt',
				mime_original: 'text/plain',
				size_bytes: 3
			},
			job: { status: 'ready', stage: 'ready', attempts: 0 },
			recommended_viewer: null
		});

		const { container } = render(SidebarWithProviders);
		const input = container.querySelector('input[type="file"]') as HTMLInputElement;
		const file = new File(['hey'], 'test.txt', { type: 'text/plain' });

		await fireEvent.change(input, { target: { files: [file] } });
		await new Promise((resolve) => setTimeout(resolve, 0));

		expect(ingestionStore.addLocalUpload).toHaveBeenCalledWith({
			id: expect.stringContaining('upload-'),
			name: 'test.txt',
			type: 'text/plain',
			size: file.size
		});
		expect(ingestionAPI.upload).toHaveBeenCalled();
		expect(ingestionStore.updateLocalUploadProgress).toHaveBeenCalled();
		expect(ingestionStore.upsertItem).toHaveBeenCalledWith({
			file: expect.objectContaining({ id: 'file-123' }),
			job: expect.objectContaining({ status: 'ready' }),
			recommended_viewer: null
		});
	});
});
