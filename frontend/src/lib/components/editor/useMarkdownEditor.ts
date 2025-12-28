import type { Editor } from '@tiptap/core';
import { Editor as TiptapEditor } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import { Image } from '@tiptap/extension-image';
import { TaskList, TaskItem } from '@tiptap/extension-list';
import { TableKit } from '@tiptap/extension-table';
import { Markdown } from 'tiptap-markdown';
import { tick } from 'svelte';

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

  const editor = new TiptapEditor({
    element,
    extensions: [
      StarterKit,
      Image.configure({ inline: false, allowBase64: true }),
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
      const markdown = editor.storage.markdown.getMarkdown();
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
        console.error('Failed to clear editor content:', error);
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
      const currentEditorContent = editor.storage.markdown.getMarkdown();
      const contentActuallyChanged = currentEditorContent !== nextContent;

      isUpdatingContent = true;

      if (contentActuallyChanged) {
        const currentPosition = editor.state.selection.anchor;

        editor.commands.setContent(nextContent);

        await tick();
        await new Promise((resolve) => requestAnimationFrame(resolve));

        if (isSameNote && currentPosition <= nextContent.length) {
          editor.commands.setTextSelection(currentPosition);
        }
      }

      lastNoteId = state.currentNoteId;
      lastContent = nextContent;

      if (isExternalUpdate && state.lastUpdateSource === 'ai') {
        onExternalUpdate();
        editorStore.clearUpdateSource();
      }
    } catch (error) {
      console.error('Failed to update editor content:', error);
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
