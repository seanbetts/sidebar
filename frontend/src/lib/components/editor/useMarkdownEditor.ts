import type { Editor } from '@tiptap/core';
import { tick } from 'svelte';
import { logError } from '$lib/utils/errorHandling';
import {
	createMarkdownExtensions,
	getEditorMarkdown,
	loadTextSelection,
	loadTiptapModules
} from '$lib/components/editor/tiptapLoader';

interface MarkdownEditorOptions {
	element: HTMLDivElement;
	editorStore: {
		subscribe: (run: (state: any) => void) => () => void;
		updateContent: (content: string) => void;
		clearUpdateSource: () => void;
	};
	onAutosave: () => void;
	onExternalUpdate: () => void;
}

/**
 * Create and wire a Tiptap markdown editor instance.
 *
 * @param options - DOM element, store hooks, and callbacks.
 * @returns Editor instance and destroy function.
 */
export function createMarkdownEditor({
	element,
	editorStore,
	onAutosave,
	onExternalUpdate
}: MarkdownEditorOptions) {
	return (async () => {
		let isUpdatingContent = false;
		let lastNoteId = '';
		let lastContent = '';
		const modules = await loadTiptapModules();
		const TextSelection = await loadTextSelection();

		const editor = new modules.Editor({
			element,
			extensions: createMarkdownExtensions(modules),
			content: '',
			editable: true,
			editorProps: {
				attributes: {
					class: 'prose prose-sm sm:prose lg:prose-lg xl:prose-xl focus:outline-none'
				}
			},
			onUpdate: ({ editor }) => {
				if (isUpdatingContent) return;
				const markdown = getEditorMarkdown(editor);
				editorStore.updateContent(markdown);
				onAutosave();
			}
		});

		const unsubscribe = editorStore.subscribe(async (state) => {
			if (!editor || state.isLoading) return;

			if (!state.currentNoteId) {
				lastNoteId = '';
				lastContent = '';
				try {
					isUpdatingContent = true;
					editor.commands.setContent('');
					await tick();
					await new Promise((resolve) => requestAnimationFrame(resolve));
				} catch (error) {
					logError('Failed to clear editor content', error, { scope: 'markdownEditor.clear' });
				} finally {
					isUpdatingContent = false;
				}
				return;
			}

			const nextContent = state.content || '';

			const isSameNote = state.currentNoteId === lastNoteId && lastNoteId !== '';
			const isExternalUpdate = isSameNote && !state.isDirty && nextContent !== lastContent;
			const shouldSync = state.currentNoteId !== lastNoteId || isExternalUpdate;

			if (!shouldSync) return;

			try {
				const currentEditorContent = getEditorMarkdown(editor);
				const contentActuallyChanged = currentEditorContent !== nextContent;

				isUpdatingContent = true;

				if (contentActuallyChanged) {
					const currentPosition = editor.state.selection.anchor;
					editor.commands.setContent(nextContent);

					await tick();
					await new Promise((resolve) => requestAnimationFrame(resolve));

					if (isSameNote) {
						const maxPosition = editor.state.doc.content.size;
						const safePosition = Math.min(currentPosition, maxPosition);
						const selection = TextSelection.near(editor.state.doc.resolve(safePosition));
						editor.view.dispatch(editor.state.tr.setSelection(selection));
					}
				}

				lastNoteId = state.currentNoteId;
				lastContent = nextContent;

				if (isExternalUpdate && state.lastUpdateSource === 'ai') {
					onExternalUpdate();
					editorStore.clearUpdateSource();
				}
			} catch (error) {
				logError('Failed to update editor content', error, { scope: 'markdownEditor.sync' });
			} finally {
				isUpdatingContent = false;
			}
		});

		const destroy = () => {
			unsubscribe();
			editor.destroy();
		};

		return {
			editor: editor as Editor,
			destroy
		};
	})();
}
