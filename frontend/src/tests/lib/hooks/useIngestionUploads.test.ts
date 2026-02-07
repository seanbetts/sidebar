import { beforeEach, describe, expect, it, vi } from 'vitest';
import { useIngestionUploads, type IngestionUploadState } from '$lib/hooks/useIngestionUploads';

const {
	ingestionAPI,
	ingestionStore,
	ingestionViewerStore,
	websitesStore,
	editorStore,
	currentNoteId,
	dispatchCacheEvent
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
	const ingestionState = createStore({ items: [] as Array<{ file: { id: string } }> });
	return {
		ingestionAPI: {
			upload: vi.fn(),
			get: vi.fn(),
			ingestYoutube: vi.fn()
		},
		ingestionStore: {
			subscribe: ingestionState.subscribe,
			addLocalUpload: vi.fn(),
			updateLocalUploadProgress: vi.fn(),
			removeLocalUpload: vi.fn(),
			upsertItem: vi.fn(),
			addLocalSource: vi.fn(() => ({ id: 'local-youtube', file: { id: 'local-youtube' } })),
			startPolling: vi.fn()
		},
		ingestionViewerStore: {
			setLocalActive: vi.fn(),
			updateActiveJob: vi.fn(),
			clearActive: vi.fn(),
			open: vi.fn()
		},
		websitesStore: {
			clearActive: vi.fn()
		},
		editorStore: {
			reset: vi.fn()
		},
		currentNoteId: {
			set: vi.fn()
		},
		dispatchCacheEvent: vi.fn()
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

vi.mock('$lib/stores/websites', () => ({
	websitesStore
}));

vi.mock('$lib/stores/editor', () => ({
	editorStore,
	currentNoteId
}));

vi.mock('$lib/utils/cacheEvents', () => ({
	dispatchCacheEvent
}));

const createState = (): { state: IngestionUploadState; getDialogOpen: () => boolean } => {
	let isUploadingFile = false;
	let isAddingYoutube = false;
	let youtubeUrl = '';
	let youtubeDialogOpen = false;

	const state: IngestionUploadState = {
		getIsUploadingFile: () => isUploadingFile,
		setIsUploadingFile: (value) => {
			isUploadingFile = value;
		},
		getIsAddingYoutube: () => isAddingYoutube,
		setIsAddingYoutube: (value) => {
			isAddingYoutube = value;
		},
		getYouTubeUrl: () => youtubeUrl,
		setYouTubeUrl: (value) => {
			youtubeUrl = value;
		},
		setYouTubeDialogOpen: (value) => {
			youtubeDialogOpen = value;
		},
		setPendingUploadId: (value) => {
			void value;
		},
		onError: vi.fn()
	};

	return {
		state,
		getDialogOpen: () => youtubeDialogOpen
	};
};

describe('useIngestionUploads', () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	it('uses ingestYoutube only for explicit YouTube add flow', async () => {
		const { state, getDialogOpen } = createState();
		state.setYouTubeUrl('https://youtu.be/dQw4w9WgXcQ');
		state.setYouTubeDialogOpen(true);

		ingestionAPI.ingestYoutube.mockResolvedValue({ file_id: 'yt-file-1' });
		ingestionAPI.get.mockResolvedValue({
			file: { id: 'yt-file-1' },
			job: { status: 'ready', stage: 'ready', attempts: 0 },
			recommended_viewer: 'video'
		});

		const handlers = useIngestionUploads(state);
		await handlers.confirmAddYouTube();

		expect(ingestionAPI.ingestYoutube).toHaveBeenCalledWith('https://youtu.be/dQw4w9WgXcQ');
		expect(ingestionStore.addLocalSource).toHaveBeenCalledWith({
			id: expect.stringContaining('youtube-'),
			name: 'YouTube video',
			mime: 'video/youtube',
			url: 'https://youtu.be/dQw4w9WgXcQ'
		});
		expect(websitesStore.clearActive).toHaveBeenCalled();
		expect(editorStore.reset).toHaveBeenCalled();
		expect(currentNoteId.set).toHaveBeenCalledWith(null);
		expect(ingestionViewerStore.open).toHaveBeenCalledWith('yt-file-1');
		expect(dispatchCacheEvent).toHaveBeenCalledWith('file.uploaded');
		expect(getDialogOpen()).toBe(false);
	});
});
