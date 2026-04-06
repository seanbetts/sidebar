import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useEditorActions } from '$lib/hooks/useEditorActions';

const { dispatchCacheEvent } = vi.hoisted(() => ({
	dispatchCacheEvent: vi.fn()
}));

const { logError } = vi.hoisted(() => ({
	logError: vi.fn()
}));

const { toast } = vi.hoisted(() => ({
	toast: {
		error: vi.fn()
	}
}));

vi.mock('$lib/utils/cacheEvents', () => ({ dispatchCacheEvent }));
vi.mock('$lib/utils/errorHandling', () => ({ logError }));
vi.mock('svelte-sonner', () => ({ toast }));

describe('useEditorActions', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.useRealTimers();
	});

	afterEach(() => {
		vi.useRealTimers();
	});

	it('retries transient rename failures before surfacing an error', async () => {
		vi.useFakeTimers();
		const fetchMock = vi
			.spyOn(global, 'fetch')
			.mockResolvedValueOnce({
				ok: false,
				status: 503,
				json: async () => ({ error: 'Service unavailable' })
			} as Response)
			.mockResolvedValueOnce({
				ok: true,
				json: async () => ({})
			} as Response);

		const editorStore = {
			reset: vi.fn(),
			saveNote: vi.fn(),
			updateNoteName: vi.fn()
		};
		const treeStore = {
			renameNoteNode: vi.fn()
		};
		let renameDialogOpen = true;
		const actions = useEditorActions({
			editorStore: editorStore as never,
			treeStore: treeStore as never,
			getCurrentNoteId: () => 'note-1',
			getDisplayTitle: () => 'Old title',
			getNoteNode: () => null,
			getIsDirty: () => false,
			getRenameValue: () => 'Renamed note',
			setRenameValue: vi.fn(),
			setIsSaveBeforeCloseDialogOpen: vi.fn(),
			setIsSaveBeforeRenameDialogOpen: vi.fn(),
			setIsRenameDialogOpen: (value: boolean) => {
				renameDialogOpen = value;
			},
			setFolderOptions: vi.fn(),
			getCopyTimeout: () => null,
			setCopyTimeout: vi.fn(),
			setIsCopied: vi.fn()
		});

		const renamePromise = actions.handleRename();
		await vi.runAllTimersAsync();
		await renamePromise;

		expect(fetchMock).toHaveBeenCalledTimes(2);
		expect(treeStore.renameNoteNode).toHaveBeenCalledWith('note-1', 'Renamed note.md');
		expect(editorStore.updateNoteName).toHaveBeenCalledWith('Renamed note.md');
		expect(dispatchCacheEvent).toHaveBeenCalledWith('note.renamed');
		expect(renameDialogOpen).toBe(false);
		expect(toast.error).not.toHaveBeenCalled();
		expect(logError).not.toHaveBeenCalled();
	});
});
