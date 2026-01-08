import { beforeEach, describe, expect, it, vi } from 'vitest';
import { get } from 'svelte/store';
import { editorStore } from '$lib/stores/editor';

describe('editorStore', () => {
	beforeEach(() => {
		vi.restoreAllMocks();
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

	it('opens preview as read-only', () => {
		editorStore.openPreview('Preview', 'Content');
		const state = get(editorStore);
		expect(state.isReadOnly).toBe(true);
		expect(state.currentNoteId).toBe('prompt-preview');
	});
});
