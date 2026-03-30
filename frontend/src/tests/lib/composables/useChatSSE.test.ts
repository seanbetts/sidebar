import { beforeEach, describe, expect, it, vi } from 'vitest';
import { useChatSSE } from '$lib/composables/useChatSSE';

const {
	sseConnectMock,
	editorStateStore,
	editorStore,
	currentNoteId,
	dispatchCacheEvent,
	dispatchSettingsRealtimeUpdate
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
			}
		};
	};

	const editorStateStore = createStore({
		currentNoteId: 'note-1',
		currentNotePath: 'note-1',
		currentNoteName: 'Note',
		content: 'Old content',
		originalContent: 'Old content',
		isDirty: false,
		isSaving: false,
		isLoading: false,
		lastSaved: null,
		saveError: null,
		basePath: 'notes',
		isReadOnly: false,
		lastUpdateSource: null
	});

	return {
		sseConnectMock: vi.fn(),
		editorStateStore,
		editorStore: {
			subscribe: editorStateStore.subscribe,
			loadNote: vi.fn(),
			applyRemoteNoteUpdate: vi.fn(),
			reset: vi.fn()
		},
		currentNoteId: {
			set: vi.fn()
		},
		dispatchCacheEvent: vi.fn(),
		dispatchSettingsRealtimeUpdate: vi.fn()
	};
});

vi.mock('$lib/api/sse', () => ({
	SSEClient: class {
		connect = sseConnectMock;
	}
}));

vi.mock('$lib/stores/chat', () => ({
	chatStore: {
		appendToken: vi.fn(),
		addToolCall: vi.fn(),
		updateToolResult: vi.fn(),
		setActiveTool: vi.fn(),
		finalizeActiveTool: vi.fn(),
		markNeedsNewline: vi.fn(),
		setPromptPreview: vi.fn()
	}
}));

vi.mock('$lib/stores/tree', () => ({
	treeStore: {
		addNoteNode: vi.fn(),
		renameNoteNode: vi.fn(),
		setNotePinned: vi.fn(),
		moveNoteNode: vi.fn(),
		removeNode: vi.fn()
	}
}));

vi.mock('$lib/stores/websites', () => ({
	websitesStore: {
		clearActive: vi.fn(),
		renameLocal: vi.fn(),
		setPinnedLocal: vi.fn(),
		updateActiveLocal: vi.fn(),
		setArchivedLocal: vi.fn(),
		removeLocal: vi.fn()
	}
}));

vi.mock('$lib/stores/editor', () => ({
	editorStore,
	currentNoteId
}));

vi.mock('$lib/stores/ingestion-viewer', () => ({
	ingestionViewerStore: {
		clearActive: vi.fn(),
		setActive: vi.fn()
	}
}));

vi.mock('$lib/stores/ingestion', () => ({
	ingestionStore: {
		upsertItem: vi.fn()
	}
}));

vi.mock('$lib/stores/scratchpad', () => ({
	scratchpadStore: {
		bump: vi.fn()
	}
}));

vi.mock('$lib/stores/memories', () => ({
	memoriesStore: {
		load: vi.fn()
	}
}));

vi.mock('$lib/stores/conversations', () => ({
	conversationListStore: {
		updateConversationTitle: vi.fn()
	}
}));

vi.mock('$lib/stores/weatherPreferences', () => ({
	weatherPreferencesStore: {
		load: vi.fn()
	}
}));

vi.mock('$lib/utils/cacheEvents', () => ({
	dispatchCacheEvent
}));

vi.mock('$lib/utils/settingsRealtime', () => ({
	dispatchSettingsRealtimeUpdate
}));

vi.mock('$lib/utils/theme', () => ({
	setThemeMode: vi.fn()
}));

vi.mock('$lib/utils/errorHandling', () => ({
	logError: vi.fn()
}));

vi.mock('svelte-sonner', () => ({
	toast: {
		error: vi.fn(),
		message: vi.fn()
	}
}));

vi.mock('$lib/utils/chatMetrics', () => ({
	markFirstEvent: vi.fn(),
	markSseError: vi.fn()
}));

vi.mock('$lib/services/api', () => ({
	ingestionAPI: {
		get: vi.fn()
	}
}));

describe('useChatSSE', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		editorStateStore.set({
			currentNoteId: 'note-1',
			currentNotePath: 'note-1',
			currentNoteName: 'Note',
			content: 'Old content',
			originalContent: 'Old content',
			isDirty: false,
			isSaving: false,
			isLoading: false,
			lastSaved: null,
			saveError: null,
			basePath: 'notes',
			isReadOnly: false,
			lastUpdateSource: null
		});
	});

	it('applies streamed content for the active note without clearing selection', async () => {
		sseConnectMock.mockImplementation(async (_payload, callbacks) => {
			await callbacks.onNoteUpdated?.({
				id: 'note-1',
				title: 'Renamed Note',
				name: 'Renamed Note',
				path: 'note-1',
				content: 'Updated content'
			});
		});

		await useChatSSE().connect({
			assistantMessageId: 'assistant-1',
			message: 'Update the note'
		});

		expect(dispatchCacheEvent).toHaveBeenCalledWith('note.updated');
		expect(editorStore.applyRemoteNoteUpdate).toHaveBeenCalledWith({
			id: 'note-1',
			title: 'Renamed Note',
			name: 'Renamed Note',
			path: 'note-1',
			content: 'Updated content'
		});
		expect(editorStore.loadNote).not.toHaveBeenCalled();
		expect(currentNoteId.set).not.toHaveBeenCalled();
	});

	it('updates website list and active website title after an AI rename', async () => {
		sseConnectMock.mockImplementation(async (_payload, callbacks) => {
			await callbacks.onWebsiteRenamed?.({
				id: 'website-1',
				title: 'Renamed website'
			});
		});

		const { websitesStore } = await import('$lib/stores/websites');

		await useChatSSE().connect({
			assistantMessageId: 'assistant-1',
			message: 'Rename the website'
		});

		expect(dispatchCacheEvent).toHaveBeenCalledWith('website.renamed');
		expect(websitesStore.renameLocal).toHaveBeenCalledWith('website-1', 'Renamed website');
		expect(websitesStore.updateActiveLocal).toHaveBeenCalledWith({ title: 'Renamed website' });
	});

	it('dispatches realtime settings updates from assistant events', async () => {
		sseConnectMock.mockImplementation(async (_payload, callbacks) => {
			await callbacks.onAssistantIdentityUpdated?.({
				assistant_identity: { name: 'Updated Assistant' },
				assistant_identity_meta: { version: 2 }
			});
			await callbacks.onAssistantSoulUpdated?.({
				assistant_soul: { purpose: 'Updated purpose' },
				assistant_soul_meta: { version: 3 }
			});
			await callbacks.onProfileUserSettingsUpdated?.({
				name: 'Sean',
				communication_style: 'Updated style'
			});
		});

		await useChatSSE().connect({
			assistantMessageId: 'assistant-1',
			message: 'Update settings'
		});

		expect(dispatchSettingsRealtimeUpdate).toHaveBeenCalledWith({
			assistant_identity: { name: 'Updated Assistant' },
			assistant_identity_meta: { version: 2 }
		});
		expect(dispatchSettingsRealtimeUpdate).toHaveBeenCalledWith({
			assistant_soul: { purpose: 'Updated purpose' },
			assistant_soul_meta: { version: 3 }
		});
		expect(dispatchSettingsRealtimeUpdate).toHaveBeenCalledWith({
			name: 'Sean',
			communication_style: 'Updated style'
		});
	});
});
