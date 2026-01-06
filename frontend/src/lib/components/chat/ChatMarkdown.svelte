<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { Editor } from '@tiptap/core';
  import StarterKit from '@tiptap/starter-kit';
  import { ImageGallery } from '$lib/components/editor/ImageGallery';
  import { ImageWithCaption } from '$lib/components/editor/ImageWithCaption';
  import { TaskList, TaskItem } from '@tiptap/extension-list';
  import { TableKit } from '@tiptap/extension-table';
  import { Markdown } from 'tiptap-markdown';

  export let content: string;

  let editorElement: HTMLDivElement;
  let editor: Editor | null = null;

  onMount(() => {
    editor = new Editor({
      element: editorElement,
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

  :global(.chat-markdown table) {
    width: 100%;
    border-collapse: collapse;
    margin: 1em 0;
    font-size: 0.95em;
  }

  :global(.chat-markdown th),
  :global(.chat-markdown td) {
    border: 1px solid var(--color-border);
    padding: 0em 0.75em;
    text-align: left;
    vertical-align: top;
  }

  :global(.chat-markdown thead th) {
    background-color: var(--color-muted);
    color: var(--color-foreground);
    font-weight: 600;
  }

  :global(.chat-markdown tbody tr:nth-child(even)) {
    background-color: color-mix(in oklab, var(--color-muted) 40%, transparent);
  }
</style>
