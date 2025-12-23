<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { Editor } from '@tiptap/core';
  import StarterKit from '@tiptap/starter-kit';
  import { TaskList, TaskItem } from '@tiptap/extension-list';
  import { Markdown } from 'tiptap-markdown';

  export let content: string;

  let editorElement: HTMLDivElement;
  let editor: Editor | null = null;

  onMount(() => {
    editor = new Editor({
      element: editorElement,
      extensions: [StarterKit, TaskList, TaskItem.configure({ nested: true }), Markdown],
      content: '',
      editable: false,
      editorProps: {
        attributes: {
          class: 'tiptap chat-markdown prose prose-sm max-w-none'
        }
      }
    });
  });

  onDestroy(() => {
    editor?.destroy();
  });

  $: if (editor) {
    editor.commands.setContent(content || '');
  }
</script>

<div bind:this={editorElement}></div>

<style>
  :global(.chat-markdown [contenteditable='false']:focus) {
    outline: none;
  }
</style>
