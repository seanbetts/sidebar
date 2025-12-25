<script lang="ts">
  import { onMount, onDestroy, tick } from 'svelte';
  import { beforeNavigate, goto } from '$app/navigation';
  import { Editor } from '@tiptap/core';
  import StarterKit from '@tiptap/starter-kit';
  import { Image } from '@tiptap/extension-image';
  import { TaskList, TaskItem } from '@tiptap/extension-list';
  import { TableKit } from '@tiptap/extension-table';
  import { Markdown } from 'tiptap-markdown';
  import { editorStore } from '$lib/stores/editor';
  import { filesStore } from '$lib/stores/files';
  import { get } from 'svelte/store';
  import { toast } from 'svelte-sonner';
  import { FileText, Save, Clock, X, Pencil, FolderInput, Archive, Pin, PinOff, Copy, Check, Download, Trash2 } from 'lucide-svelte';
  import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';
  import * as Popover from '$lib/components/ui/popover/index.js';
  import { Button } from '$lib/components/ui/button';
  import NoteDeleteDialog from '$lib/components/files/NoteDeleteDialog.svelte';

  let editorElement: HTMLDivElement;
  let editor: Editor | null = null;
  let saveTimeout: ReturnType<typeof setTimeout>;
  let unsubscribe: (() => void) | undefined;

  // Flag to prevent infinite loops:
  // When we programmatically update the editor (e.g., loading a note or AI updates),
  // we don't want that to trigger onUpdate which would mark the note as dirty
  let isUpdatingContent = false;
  let isLeaveDialogOpen = false;
  let pendingHref: string | null = null;
  let allowNavigateOnce = false;
  let isRenameDialogOpen = false;
  let renameValue = '';
  let renameInput: HTMLInputElement | null = null;
  let isDeleteDialogOpen = false;
  let folderOptions: { label: string; value: string; depth: number }[] = [];
  let copyTimeout: ReturnType<typeof setTimeout> | null = null;
  let isCopied = false;

  $: isDirty = $editorStore.isDirty;
  $: isSaving = $editorStore.isSaving;
  $: lastSaved = $editorStore.lastSaved;
  $: saveError = $editorStore.saveError;
  $: currentNoteName = $editorStore.currentNoteName;
  $: isLoading = $editorStore.isLoading;
  $: currentNoteId = $editorStore.currentNoteId;
  $: isReadOnly = $editorStore.isReadOnly;

  // Strip file extension from note name for display
  $: displayTitle = currentNoteName ? currentNoteName.replace(/\.[^/.]+$/, '') : '';

  function findNoteNode(noteId: string | null, tree: any) {
    if (!noteId) return null;
    const nodes = tree?.children || [];
    const walk = (items: any[]): any | null => {
      for (const item of items) {
        if (item.type === 'file' && item.path === noteId) return item;
        if (item.children) {
          const match = walk(item.children);
          if (match) return match;
        }
      }
      return null;
    };
    return walk(nodes);
  }

  $: noteNode = findNoteNode(currentNoteId, $filesStore.trees['notes']);

  function buildFolderOptions() {
    const tree = get(filesStore).trees['notes'];
    const nodes = tree?.children || [];
    const options: { label: string; value: string; depth: number }[] = [
      { label: 'Notes', value: '', depth: 0 }
    ];

    const walk = (items: any[], depth: number) => {
      for (const item of items) {
        if (item.type !== 'directory') continue;
        if (item.name === 'Archive') continue;
        const folderPath = item.path.replace(/^folder:/, '');
        options.push({ label: item.name, value: folderPath, depth });
        if (item.children?.length) {
          walk(item.children, depth + 1);
        }
      }
    };

    walk(nodes, 1);
    folderOptions = options;
  }

  async function handleClose() {
    if (isDirty) {
      const save = confirm('Save changes before closing this note?');
      if (save) {
        await editorStore.saveNote();
      }
    }
    editorStore.reset();
  }

  function openRenameDialog() {
    renameValue = displayTitle;
    isRenameDialogOpen = true;
  }

  async function handleRename() {
    if (!currentNoteId) return;
    const trimmed = renameValue.trim();
    if (!trimmed || trimmed === displayTitle) {
      isRenameDialogOpen = false;
      return;
    }
    if (isDirty) {
      const save = confirm('Save changes before renaming this note?');
      if (save) {
        await editorStore.saveNote();
      }
    }
    const response = await fetch(`/api/notes/${currentNoteId}/rename`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ newName: `${trimmed}.md` })
    });
    if (!response.ok) {
      console.error('Failed to rename note');
      return;
    }
    await filesStore.load('notes');
    await editorStore.loadNote('notes', currentNoteId, { source: 'user' });
    isRenameDialogOpen = false;
  }

  async function handleMove(folder: string) {
    if (!currentNoteId) return;
    const response = await fetch(`/api/notes/${currentNoteId}/move`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ folder })
    });
    if (!response.ok) {
      console.error('Failed to move note');
      return;
    }
    await filesStore.load('notes');
  }

  async function handleArchive() {
    if (!currentNoteId) return;
    const response = await fetch(`/api/notes/${currentNoteId}/archive`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ archived: true })
    });
    if (!response.ok) {
      console.error('Failed to archive note');
      return;
    }
    await filesStore.load('notes');
    editorStore.reset();
  }

  async function handlePinToggle() {
    if (!currentNoteId) return;
    const node = noteNode;
    const pinned = !(node?.pinned);
    const response = await fetch(`/api/notes/${currentNoteId}/pin`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pinned })
    });
    if (!response.ok) {
      console.error('Failed to update pin');
      return;
    }
    await filesStore.load('notes');
  }

  async function handleDownload() {
    if (!currentNoteId) return;
    const link = document.createElement('a');
    link.href = `/api/notes/${currentNoteId}/download`;
    link.download = `${displayTitle || 'note'}.md`;
    document.body.appendChild(link);
    link.click();
    link.remove();
  }

  async function handleCopy() {
    if (!currentNoteId) return;
    try {
      await navigator.clipboard.writeText($editorStore.content || '');
      isCopied = true;
      if (copyTimeout) clearTimeout(copyTimeout);
      copyTimeout = setTimeout(() => {
        isCopied = false;
        copyTimeout = null;
      }, 1500);
    } catch (error) {
      console.error('Failed to copy note content:', error);
    }
  }

  async function handleDelete() {
    if (!currentNoteId) return;
    const response = await fetch(`/api/notes/${currentNoteId}`, {
      method: 'DELETE'
    });
    if (!response.ok) {
      console.error('Failed to delete note');
      return;
    }
    await filesStore.load('notes');
    editorStore.reset();
    isDeleteDialogOpen = false;
  }

  onMount(() => {
    editor = new Editor({
      element: editorElement,
      extensions: [
        StarterKit,
        Image.configure({ inline: false, allowBase64: true }),
        TaskList,
        TaskItem.configure({ nested: true }),
        TableKit,
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
    let lastContent = '';
    unsubscribe = editorStore.subscribe(async state => {
      if (!editor || state.isLoading) return;

      if (!state.currentNoteId) {
        lastNoteId = '';
        lastContent = '';
        try {
          isUpdatingContent = true;
          editor.commands.setContent('');
          await tick();
          await new Promise(resolve => requestAnimationFrame(resolve));
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
      const shouldSync =
        state.currentNoteId !== lastNoteId ||
        isExternalUpdate;

      if (!shouldSync) return;

      try {
        // Get current editor content to check if update is actually needed
        const currentEditorContent = editor.storage.markdown.getMarkdown();
        const contentActuallyChanged = currentEditorContent !== nextContent;

        // Set flag to prevent onUpdate from firing
        isUpdatingContent = true;

        // Only update editor if content actually changed
        if (contentActuallyChanged) {
          // Save cursor position before updating content
          const currentPosition = editor.state.selection.anchor;

          // Set content directly (no need to clear first)
          editor.commands.setContent(nextContent);

          // Wait for Svelte reactivity and browser render
          await tick();
          await new Promise(resolve => requestAnimationFrame(resolve));

          // Restore cursor position if it's still valid
          // (Only restore if we're at the same note, not switching notes)
          if (isSameNote && currentPosition <= nextContent.length) {
            editor.commands.setTextSelection(currentPosition);
          }
        }

        // Update tracking variables AFTER editor has updated
        lastNoteId = state.currentNoteId;
        lastContent = nextContent;

        if (isExternalUpdate && state.lastUpdateSource === 'ai') {
          toast.message('Note updated');
          editorStore.clearUpdateSource();
        }
      } catch (error) {
        console.error('Failed to update editor content:', error);
        // Don't update tracking variables if update failed
      } finally {
        isUpdatingContent = false;
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

  $: if (isRenameDialogOpen) {
    tick().then(() => {
      renameInput?.focus();
      renameInput?.select();
    });
  }

  $: if (editor) {
    editor.setEditable(!isReadOnly);
  }

  onDestroy(() => {
    // Cleanup all timers and subscriptions
    clearTimeout(saveTimeout);
    if (copyTimeout) clearTimeout(copyTimeout);
    if (unsubscribe) unsubscribe();
    if (editor) editor.destroy();
  });

  function scheduleAutoSave() {
    clearTimeout(saveTimeout);
    if ($editorStore.isDirty && !$editorStore.isReadOnly) {
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

<AlertDialog.Root bind:open={isRenameDialogOpen}>
  <AlertDialog.Content
    onOpenAutoFocus={(event) => {
      event.preventDefault();
      renameInput?.focus();
      renameInput?.select();
    }}
  >
    <AlertDialog.Header>
      <AlertDialog.Title>Rename note</AlertDialog.Title>
      <AlertDialog.Description>Update the note title.</AlertDialog.Description>
    </AlertDialog.Header>
    <div class="py-2">
      <input
        class="w-full rounded-md border bg-background px-3 py-2 text-sm shadow-sm outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
        type="text"
        placeholder="Note title"
        bind:this={renameInput}
        bind:value={renameValue}
        on:keydown={(event) => {
          if (event.key === 'Enter') handleRename();
        }}
      />
    </div>
    <AlertDialog.Footer>
      <AlertDialog.Cancel onclick={() => (isRenameDialogOpen = false)}>Cancel</AlertDialog.Cancel>
      <AlertDialog.Action disabled={!renameValue.trim()} onclick={handleRename}>
        Rename
      </AlertDialog.Action>
    </AlertDialog.Footer>
  </AlertDialog.Content>
</AlertDialog.Root>

<NoteDeleteDialog
  bind:open={isDeleteDialogOpen}
  itemType="note"
  itemName={displayTitle}
  onConfirm={handleDelete}
  onCancel={() => (isDeleteDialogOpen = false)}
/>

<div class="editor-container">
  {#if currentNoteName}
    <div class="editor-header">
      <div class="header-left">
        <FileText size={20} />
        <h2 class="note-title">{displayTitle}</h2>
      </div>
      <div class="header-right">
        {#if isReadOnly}
          <span class="status saved">Read-only preview</span>
        {:else if saveError}
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
        <div class="note-actions">
          {#if isReadOnly}
            <Button
              size="icon"
              variant="ghost"
              onclick={handleCopy}
              aria-label={isCopied ? 'Copied preview' : 'Copy preview'}
              title={isCopied ? 'Copied' : 'Copy preview'}
            >
              {#if isCopied}
                <Check size={16} />
              {:else}
                <Copy size={16} />
              {/if}
            </Button>
            <Button
              size="icon"
              variant="ghost"
              onclick={handleClose}
              aria-label="Close preview"
              title="Close preview"
            >
              <X size={16} />
            </Button>
          {:else}
            <Button
              size="icon"
              variant="ghost"
              onclick={handlePinToggle}
              aria-label="Pin note"
              title="Pin note"
            >
              {#if noteNode?.pinned}
                <PinOff size={16} />
              {:else}
                <Pin size={16} />
              {/if}
            </Button>
            <Button
              size="icon"
              variant="ghost"
              onclick={openRenameDialog}
              aria-label="Rename note"
              title="Rename note"
            >
              <Pencil size={16} />
            </Button>
            <Popover.Root onOpenChange={(open) => open && buildFolderOptions()}>
              <Popover.Trigger>
                {#snippet child({ props })}
                  <Button size="icon" variant="ghost" {...props} aria-label="Move note" title="Move note">
                    <FolderInput size={16} />
                  </Button>
                {/snippet}
              </Popover.Trigger>
              <Popover.Content class="note-move-menu" align="start" sideOffset={8}>
                {#each folderOptions as option (option.value)}
                  <button
                    class="note-move-item"
                    style={`padding-left: ${option.depth * 12 + 12}px`}
                    on:click={() => handleMove(option.value)}
                  >
                    {option.label}
                  </button>
                {/each}
              </Popover.Content>
            </Popover.Root>
            <Button
              size="icon"
              variant="ghost"
              onclick={handleCopy}
              aria-label={isCopied ? 'Copied note' : 'Copy note'}
              title={isCopied ? 'Copied' : 'Copy note'}
            >
              {#if isCopied}
                <Check size={16} />
              {:else}
                <Copy size={16} />
              {/if}
            </Button>
            <Button
              size="icon"
              variant="ghost"
              onclick={handleDownload}
              aria-label="Download note"
              title="Download note"
            >
              <Download size={16} />
            </Button>
            <Button
              size="icon"
              variant="ghost"
              onclick={handleArchive}
              aria-label="Archive note"
              title="Archive note"
            >
              <Archive size={16} />
            </Button>
            <Button
              size="icon"
              variant="ghost"
              onclick={() => (isDeleteDialogOpen = true)}
              aria-label="Delete note"
              title="Delete note"
            >
              <Trash2 size={16} />
            </Button>
            <Button
              size="icon"
              variant="ghost"
              onclick={handleClose}
              aria-label="Close note"
              title="Close note"
            >
              <X size={16} />
            </Button>
          {/if}
        </div>
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
    height: 100%;
    min-height: 0;
    background-color: var(--color-background);
  }

  .editor-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.5rem 1.5rem;
    min-height: 57px;
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
    line-height: 1.2;
  }

  .header-right {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .note-actions {
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
  }

  .status {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.75rem;
    padding: 0 0.75rem;
    border-radius: 0.375rem;
  }

  .note-move-menu {
    width: 220px;
    padding: 0.25rem 0;
  }

  .note-move-item {
    display: block;
    width: 100%;
    border: none;
    background: none;
    cursor: pointer;
    padding: 0.4rem 0.75rem;
    text-align: left;
    font-size: 0.8rem;
    color: var(--color-popover-foreground);
  }

  .note-move-item:hover {
    background-color: var(--color-accent);
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
    padding: 1rem 2rem;
    min-height: 0;
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
    margin-top: 0.5em;
    margin-bottom: 0.5em;
    color: var(--color-foreground);
  }

  :global(.tiptap h3) {
    font-size: 1.25em;
    font-weight: 600;
    margin-top: 0.5em;
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

  :global(.tiptap ul[data-type='taskList'] input[type='checkbox']) {
    accent-color: #000;
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

  :global(.tiptap table) {
    width: 100%;
    border-collapse: collapse;
    margin: 1em 0;
    font-size: 0.95em;
  }

  :global(.tiptap th),
  :global(.tiptap td) {
    border: 1px solid var(--color-border);
    padding: 0em 0.75em;
    text-align: left;
    vertical-align: top;
  }

  :global(.tiptap thead th) {
    background-color: var(--color-muted);
    color: var(--color-foreground);
    font-weight: 600;
  }

  :global(.tiptap tbody tr:nth-child(even)) {
    background-color: color-mix(in oklab, var(--color-muted) 40%, transparent);
  }

  :global(.tiptap a) {
    color: var(--color-primary);
    text-decoration: underline;
  }

  :global(.tiptap a:hover) {
    cursor: pointer;
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
