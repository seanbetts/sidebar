<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { beforeNavigate, goto } from '$app/navigation';
  import { Editor } from '@tiptap/core';
  import StarterKit from '@tiptap/starter-kit';
  import { TaskList, TaskItem } from '@tiptap/extension-list';
  import { Markdown } from 'tiptap-markdown';
  import { editorStore } from '$lib/stores/editor';
  import { FileText, Save, Clock } from 'lucide-svelte';
  import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';

  let editorElement: HTMLDivElement;
  let editor: Editor | null = null;
  let saveTimeout: ReturnType<typeof setTimeout>;
  let unsubscribe: (() => void) | undefined;
  let isUpdatingContent = false; // Flag to prevent onUpdate during programmatic changes
  let isLeaveDialogOpen = false;
  let pendingHref: string | null = null;
  let allowNavigateOnce = false;

  $: isDirty = $editorStore.isDirty;
  $: isSaving = $editorStore.isSaving;
  $: lastSaved = $editorStore.lastSaved;
  $: saveError = $editorStore.saveError;
  $: currentNoteName = $editorStore.currentNoteName;
  $: isLoading = $editorStore.isLoading;

  // Strip file extension from note name for display
  $: displayTitle = currentNoteName ? currentNoteName.replace(/\.[^/.]+$/, '') : '';

  onMount(() => {
    editor = new Editor({
      element: editorElement,
      extensions: [
        StarterKit,
        TaskList,
        TaskItem.configure({ nested: true }),
        Markdown  // Enables markdown shortcuts and parsing
      ],
      content: '',
      editable: true,
      editorProps: {
        attributes: {
          class: 'prose prose-sm sm:prose lg:prose-lg xl:prose-xl focus:outline-none'
        }
      },
      onUpdate: ({ editor }) => {
        // Skip updates when we're programmatically setting content
        if (isUpdatingContent) return;

        const markdown = editor.storage.markdown.getMarkdown();
        editorStore.updateContent(markdown);
        scheduleAutoSave();
      }
    });

    // Update editor when store changes (e.g., loading new note)
    let lastNoteId = '';
    unsubscribe = editorStore.subscribe(state => {
      // Only update editor when switching to a different note, not on every content change
      if (editor && !state.isLoading && state.currentNoteId && state.currentNoteId !== lastNoteId) {
        lastNoteId = state.currentNoteId;

        // Set flag to prevent onUpdate from firing
        isUpdatingContent = true;

        // Clear editor first, then set content
        editor.commands.clearContent();
        editor.commands.setContent(state.content || '');

        // Reset flag after a microtask to allow the update to complete
        setTimeout(() => {
          isUpdatingContent = false;
        }, 0);
      }
    });
  });

  beforeNavigate(({ cancel, to }) => {
    if (allowNavigateOnce) {
      allowNavigateOnce = false;
      return;
    }
    if ($editorStore.isDirty) {
      cancel();
      pendingHref = to?.url?.href ?? null;
      isLeaveDialogOpen = true;
    }
  });

  onDestroy(() => {
    clearTimeout(saveTimeout);
    if (unsubscribe) {
      unsubscribe();
    }
    if (editor) {
      editor.destroy();
    }
  });

  function scheduleAutoSave() {
    clearTimeout(saveTimeout);
    if ($editorStore.isDirty) {
      saveTimeout = setTimeout(() => {
        editorStore.saveNote();
      }, 1500);
    }
  }

  function formatLastSaved(date: Date | null): string {
    if (!date) return '';
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffSecs = Math.floor(diffMs / 1000);

    if (diffSecs < 60) return 'just now';
    if (diffSecs < 3600) return `${Math.floor(diffSecs / 60)}m ago`;
    return date.toLocaleTimeString();
  }

  function stayOnPage() {
    isLeaveDialogOpen = false;
    pendingHref = null;
  }

  async function confirmLeave() {
    isLeaveDialogOpen = false;
    if (!pendingHref) return;
    allowNavigateOnce = true;
    await goto(pendingHref);
    pendingHref = null;
  }
</script>

<AlertDialog.Root bind:open={isLeaveDialogOpen}>
  <AlertDialog.Content>
    <AlertDialog.Header>
      <AlertDialog.Title>Leave without saving?</AlertDialog.Title>
      <AlertDialog.Description>
        You have unsaved changes. If you leave now, they will be lost.
      </AlertDialog.Description>
    </AlertDialog.Header>
    <AlertDialog.Footer>
      <AlertDialog.Cancel onclick={stayOnPage}>Stay</AlertDialog.Cancel>
      <AlertDialog.Action onclick={confirmLeave}>
        Leave
      </AlertDialog.Action>
    </AlertDialog.Footer>
  </AlertDialog.Content>
</AlertDialog.Root>

<div class="editor-container">
  {#if currentNoteName}
    <div class="editor-header">
      <div class="header-left">
        <FileText size={20} />
        <h2 class="note-title">{displayTitle}</h2>
      </div>
      <div class="header-right">
        {#if saveError}
          <span class="status error">{saveError}</span>
        {:else if isSaving}
          <span class="status saving">
            <Save size={16} class="spin" />
            Saving...
          </span>
        {:else if isDirty}
          <span class="status unsaved">Unsaved changes</span>
        {:else if lastSaved}
          <span class="status saved">
            <Clock size={16} />
            Saved {formatLastSaved(lastSaved)}
          </span>
        {/if}
      </div>
    </div>
  {/if}

  <!-- TipTap Editor - always rendered -->
  <div class="editor-scroll" class:hidden={!currentNoteName}>
    <div bind:this={editorElement} class="tiptap-editor"></div>
  </div>

  <!-- Empty state - shown when no note selected -->
  {#if !currentNoteName}
    <div class="empty-state">
      <FileText size={64} />
      <h2>No note selected</h2>
      <p>Select a note from the sidebar to start editing</p>
    </div>
  {/if}
</div>

<style>
  .editor-container {
    display: flex;
    flex-direction: column;
    height: 100vh;
    background-color: var(--color-background);
  }

  .editor-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1rem 1.5rem;
    border-bottom: 1px solid var(--color-border);
    background-color: var(--color-card);
    flex-shrink: 0;
  }

  .header-left {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    color: var(--color-foreground);
  }

  .note-title {
    margin: 0;
    font-size: 1.125rem;
    font-weight: 600;
  }

  .header-right {
    display: flex;
    align-items: center;
  }

  .status {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.875rem;
    padding: 0.375rem 0.75rem;
    border-radius: 0.375rem;
  }

  .status.saving {
    color: var(--color-primary);
    background-color: var(--color-primary-muted);
  }

  .status.saved {
    color: var(--color-success);
    background-color: var(--color-success-muted);
  }

  .status.unsaved {
    color: var(--color-warning);
    background-color: var(--color-warning-muted);
  }

  .status.error {
    color: var(--color-destructive);
    background-color: var(--color-destructive-muted);
  }

  .editor-scroll {
    flex: 1;
    overflow-y: auto;
    padding: 2rem;
  }

  .editor-scroll.hidden {
    display: none;
  }

  .tiptap-editor {
    max-width: 85ch;
    margin: 0 auto;
  }

  .empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 100%;
    color: var(--color-muted-foreground);
    text-align: center;
  }

  .empty-state h2 {
    margin-top: 1rem;
    margin-bottom: 0.5rem;
    font-size: 1.5rem;
    font-weight: 600;
  }

  .empty-state p {
    font-size: 1rem;
  }

  /* TipTap prose styling */
  :global(.tiptap) {
    outline: none;
    min-height: 100%;
    color: var(--color-foreground);
  }

  :global(.tiptap h1) {
    font-size: 2em;
    font-weight: 700;
    margin-top: 0;
    margin-bottom: 0.5em;
    color: var(--color-foreground);
  }

  :global(.tiptap h2) {
    font-size: 1.5em;
    font-weight: 600;
    margin-top: 1.5em;
    margin-bottom: 0.5em;
    color: var(--color-foreground);
  }

  :global(.tiptap h3) {
    font-size: 1.25em;
    font-weight: 600;
    margin-top: 1.25em;
    margin-bottom: 0.5em;
    color: var(--color-foreground);
  }

  :global(.tiptap p) {
    margin-top: 0.75em;
    margin-bottom: 0.75em;
    line-height: 1.7;
  }

  :global(.tiptap strong) {
    font-weight: 700;
  }

  :global(.tiptap em) {
    font-style: italic;
  }

  :global(.tiptap code) {
    background-color: var(--color-muted);
    color: var(--color-foreground);
    padding: 0.2em 0.4em;
    border-radius: 0.25em;
    font-size: 0.875em;
    font-family: ui-monospace, 'Cascadia Code', 'Source Code Pro', Menlo, Consolas, 'DejaVu Sans Mono', monospace;
  }

  :global(.tiptap pre) {
    background-color: var(--color-muted);
    color: var(--color-foreground);
    padding: 1em;
    border-radius: 0.5em;
    overflow-x: auto;
    margin: 1em 0;
  }

  :global(.tiptap pre code) {
    background-color: transparent;
    padding: 0;
    font-size: 0.875em;
  }

  :global(.tiptap ul), :global(.tiptap ol) {
    margin-top: 0.75em;
    margin-bottom: 0.75em;
    padding-left: 1.5em;
  }

  :global(.tiptap li > ul),
  :global(.tiptap li > ol) {
    margin-top: 0;
    margin-bottom: 0;
  }

  :global(.tiptap ul) {
    list-style-type: disc;
  }

  :global(.tiptap ol) {
    list-style-type: decimal;
  }

  :global(.tiptap li) {
    margin-top: 0 !important;
    margin-bottom: 0 !important;
    line-height: 1.4;
  }

  :global(.tiptap li p) {
    margin-top: 0 !important;
    margin-bottom: 0 !important;
  }

  :global(.tiptap ul[data-type='taskList']) {
    list-style: none;
    padding-left: 0;
  }

  :global(.tiptap ul[data-type='taskList'] ul[data-type='taskList']) {
    margin-top: 0;
    margin-bottom: 0;
  }

  :global(.tiptap ul[data-type='taskList'] > li) {
    display: flex;
    align-items: flex-start;
    gap: 0.5em;
  }

  :global(.tiptap ul[data-type='taskList'] > li > label) {
    margin-top: 0.2em;
  }

  :global(.tiptap ul[data-type='taskList'] > li > div) {
    flex: 1;
  }

  :global(.tiptap ul[data-type='taskList'] > li > div > p) {
    margin: 0;
  }

  :global(.tiptap ul[data-type='taskList'] > li > div > p:empty) {
    display: none;
  }

  :global(.tiptap ul[data-type='taskList'] > li[data-checked='true'] > div) {
    color: var(--color-muted-foreground);
    text-decoration: line-through;
  }

  :global(.tiptap blockquote) {
    border-left: 3px solid var(--color-border);
    padding-left: 1em;
    margin-left: 0;
    margin-top: 1em;
    margin-bottom: 1em;
    color: var(--color-muted-foreground);
  }

  :global(.tiptap hr) {
    border: none;
    border-top: 1px solid var(--color-border);
    margin: 2em 0;
  }

  :global(.tiptap a) {
    color: var(--color-primary);
    text-decoration: underline;
  }

  :global(.tiptap a:hover) {
    opacity: 0.8;
  }

  /* Spin animation for saving icon */
  :global(.spin) {
    animation: spin 1s linear infinite;
  }

  @keyframes spin {
    from {
      transform: rotate(0deg);
    }
    to {
      transform: rotate(360deg);
    }
  }
</style>
