import { beforeEach, describe, expect, it, vi } from 'vitest';
import { get } from 'svelte/store';
import { editorStore } from '$lib/stores/editor';

describe('editorStore', () => {
	beforeEach(() => {
		vi.restoreAllMocks();
		vi.useRealTimers();
		editorStore.reset();
	});

	it('loads a note and sets content', async () => {
		vi.spyOn(global, 'fetch').mockResolvedValue({
			ok: true,
			json: async () => ({ path: 'note-1', name: 'Note', content: 'Hello' })
		} as Response);

		await editorStore.loadNote('notes', 'note-1');

		const state = get(editorStore);
		expect(state.content).toBe('Hello');
		expect(state.isDirty).toBe(false);
	});

	it('updates content and marks dirty', () => {
		editorStore.updateContent('New content');
		const state = get(editorStore);
		expect(state.isDirty).toBe(true);
	});

	it('saves note content', async () => {
		vi.spyOn(global, 'fetch').mockResolvedValue({ ok: true, json: async () => ({}) } as Response);
		await editorStore.loadNote('notes', 'note-1');
		editorStore.updateContent('Updated');

		await editorStore.saveNote();

		const state = get(editorStore);
		expect(state.isDirty).toBe(false);
		expect(state.saveError).toBeNull();
	});

	it('retries transient note save failures before surfacing an error', async () => {
		vi.useFakeTimers();
		const fetchMock = vi
			.spyOn(global, 'fetch')
			.mockResolvedValueOnce({
				ok: true,
				json: async () => ({ path: 'note-1', name: 'Note', content: 'Hello' })
			} as Response)
			.mockResolvedValueOnce({
				ok: false,
				status: 503,
				json: async () => ({ error: 'Service unavailable' })
			} as Response)
			.mockResolvedValueOnce({ ok: true, json: async () => ({}) } as Response);

		await editorStore.loadNote('notes', 'note-1');
		editorStore.updateContent('Updated');

		const savePromise = editorStore.saveNote();
		await vi.runAllTimersAsync();
		await savePromise;

		const state = get(editorStore);
		expect(fetchMock).toHaveBeenCalledTimes(3);
		expect(state.isDirty).toBe(false);
		expect(state.saveError).toBeNull();
	});

	it('opens preview as read-only', () => {
		editorStore.openPreview('Preview', 'Content');
		const state = get(editorStore);
		expect(state.isReadOnly).toBe(true);
		expect(state.currentNoteId).toBe('prompt-preview');
	});

	it('applies a streamed note update to the active note', async () => {
		vi.spyOn(global, 'fetch').mockResolvedValue({
			ok: true,
			json: async () => ({ path: 'note-1', name: 'Note', content: 'Hello' })
		} as Response);

		await editorStore.loadNote('notes', 'note-1');

		editorStore.applyRemoteNoteUpdate({
			id: 'note-1',
			name: 'Renamed Note',
			path: 'note-1',
			content: 'Updated content'
		});

		const state = get(editorStore);
		expect(state.currentNoteName).toBe('Renamed Note');
		expect(state.content).toBe('Updated content');
		expect(state.originalContent).toBe('Updated content');
		expect(state.isDirty).toBe(false);
		expect(state.lastUpdateSource).toBe('ai');
	});
});
