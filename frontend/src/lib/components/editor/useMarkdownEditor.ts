import type { Editor } from '@tiptap/core';
import { Editor as TiptapEditor } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import { ImageGallery } from '$lib/components/editor/ImageGallery';
import { ImageWithCaption } from '$lib/components/editor/ImageWithCaption';
import { TaskList, TaskItem } from '@tiptap/extension-list';
import { TableKit } from '@tiptap/extension-table';
import { Markdown } from 'tiptap-markdown';
import { tick } from 'svelte';
import { TextSelection } from '@tiptap/pm/state';
import { logError } from '$lib/utils/errorHandling';

type MarkdownStorage = {
	markdown: { getMarkdown: () => string };
};

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
	let isUpdatingContent = false;
	let lastNoteId = '';
	let lastContent = '';
	const getMarkdown = (editor: Editor) =>
		(editor as Editor & { storage: MarkdownStorage }).storage.markdown.getMarkdown();

	const editor = new TiptapEditor({
		element,
		extensions: [
			StarterKit,
			ImageGallery,
			ImageWithCaption.configure({ inline: false, allowBase64: true }),
			TaskList,
			TaskItem.configure({ nested: true }),
			TableKit,
			Markdown
		],
		content: '',
		editable: true,
		editorProps: {
			attributes: {
				class: 'prose prose-sm sm:prose lg:prose-lg xl:prose-xl focus:outline-none'
			}
		},
		onUpdate: ({ editor }) => {
			if (isUpdatingContent) return;
			const markdown = getMarkdown(editor);
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
			const currentEditorContent = getMarkdown(editor);
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
}
