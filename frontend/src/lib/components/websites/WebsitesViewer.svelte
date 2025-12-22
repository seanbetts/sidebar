<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { Editor } from '@tiptap/core';
  import StarterKit from '@tiptap/starter-kit';
  import { TaskList, TaskItem } from '@tiptap/extension-list';
  import { Markdown } from 'tiptap-markdown';
  import { Globe } from 'lucide-svelte';
  import { websitesStore } from '$lib/stores/websites';

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
          class: 'tiptap website-viewer'
        }
      }
    });
  });

  onDestroy(() => {
    if (editor) editor.destroy();
  });

  $: if (editor && $websitesStore.active) {
    editor.commands.setContent($websitesStore.active.content || '');
  }
</script>

<div class="website-pane">
  <div class="website-header">
    {#if $websitesStore.active}
      <div class="website-meta">
        <div class="title-row">
          <span class="title-text">{$websitesStore.active.title}</span>
          {#if $websitesStore.active.published_at}
            <span class="published-date">
              {new Date($websitesStore.active.published_at).toLocaleDateString()}
            </span>
          {/if}
        </div>
        <a class="source" href={$websitesStore.active.url} target="_blank" rel="noopener noreferrer">
          <Globe size={14} />
          <span>{$websitesStore.active.domain}</span>
        </a>
      </div>
    {/if}
  </div>
  <div class="website-body">
    <div bind:this={editorElement} class="website-content"></div>
  </div>
</div>

<style>
  .website-pane {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
  }

  .website-header {
    display: flex;
    align-items: center;
    justify-content: flex-start;
    gap: 1rem;
    padding: 1rem 1.5rem;
    border-bottom: 1px solid var(--color-border);
    background-color: var(--color-card);
  }

  .website-meta {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 0.2rem;
  }

  .title-row {
    display: inline-flex;
    align-items: baseline;
    gap: 0.5rem;
  }

  .title-text {
    font-size: 1rem;
    font-weight: 600;
    color: var(--color-foreground);
  }

  .published-date {
    font-size: 0.8rem;
    color: var(--color-muted-foreground);
  }

  .website-meta .source {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
    font-size: 0.8rem;
    color: var(--color-muted-foreground);
    text-decoration: none;
  }

  .website-body {
    flex: 1;
    min-height: 0;
    overflow: auto;
    padding: 1.5rem 2rem 2rem;
  }

  :global(.website-viewer [contenteditable='false']:focus) {
    outline: none;
  }
</style>
