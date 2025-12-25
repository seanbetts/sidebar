<script lang="ts">
  import { onDestroy, onMount, tick } from 'svelte';
  import { Editor } from '@tiptap/core';
  import StarterKit from '@tiptap/starter-kit';
  import { Image } from '@tiptap/extension-image';
  import { TaskList, TaskItem } from '@tiptap/extension-list';
  import { TableKit } from '@tiptap/extension-table';
  import { Markdown } from 'tiptap-markdown';
  import { Globe, Pin, PinOff, Pencil, Copy, Check, Download, Archive, Trash2, X } from 'lucide-svelte';
  import { websitesStore } from '$lib/stores/websites';
  import { Button } from '$lib/components/ui/button';
  import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';
  import NoteDeleteDialog from '$lib/components/files/NoteDeleteDialog.svelte';

  let editorElement: HTMLDivElement;
  let editor: Editor | null = null;
  let isRenameDialogOpen = false;
  let renameValue = '';
  let renameInput: HTMLInputElement | null = null;
  let isDeleteDialogOpen = false;
  let copyTimeout: ReturnType<typeof setTimeout> | null = null;
  let isCopied = false;

  function formatDateWithOrdinal(date: Date) {
    const day = date.getDate();
    const suffix = day % 100 >= 11 && day % 100 <= 13
      ? 'th'
      : day % 10 === 1
        ? 'st'
        : day % 10 === 2
          ? 'nd'
          : day % 10 === 3
            ? 'rd'
            : 'th';
    const month = date.toLocaleDateString(undefined, { month: 'long' });
    const year = date.getFullYear();
    return `${day}${suffix} ${month} ${year}`;
  }

  function formatDomain(domain: string) {
    return domain.replace(/^www\./i, '');
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
        Markdown
      ],
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
    if (copyTimeout) clearTimeout(copyTimeout);
  });

  $: if (editor && $websitesStore.active) {
    editor.commands.setContent($websitesStore.active.content || '');
  }

  function openRenameDialog() {
    if (!$websitesStore.active) return;
    renameValue = $websitesStore.active.title || '';
    isRenameDialogOpen = true;
  }

  async function handleRename() {
    const active = $websitesStore.active;
    if (!active) return;
    const trimmed = renameValue.trim();
    if (!trimmed || trimmed === active.title) {
      isRenameDialogOpen = false;
      return;
    }
    const response = await fetch(`/api/websites/${active.id}/rename`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: trimmed })
    });
    if (!response.ok) {
      console.error('Failed to rename website');
      return;
    }
    await websitesStore.load();
    await websitesStore.loadById(active.id);
    isRenameDialogOpen = false;
  }

  async function handlePinToggle() {
    const active = $websitesStore.active;
    if (!active) return;
    const response = await fetch(`/api/websites/${active.id}/pin`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pinned: !active.pinned })
    });
    if (!response.ok) {
      console.error('Failed to update pin');
      return;
    }
    await websitesStore.load();
    await websitesStore.loadById(active.id);
  }

  async function handleArchive() {
    const active = $websitesStore.active;
    if (!active) return;
    const response = await fetch(`/api/websites/${active.id}/archive`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ archived: !active.archived })
    });
    if (!response.ok) {
      console.error('Failed to archive website');
      return;
    }
    await websitesStore.load();
    if (active.archived) {
      await websitesStore.loadById(active.id);
    } else {
      websitesStore.clearActive();
    }
  }

  async function handleDownload() {
    const active = $websitesStore.active;
    if (!active) return;
    const link = document.createElement('a');
    link.href = `/api/websites/${active.id}/download`;
    link.download = `${active.title || 'website'}.md`;
    document.body.appendChild(link);
    link.click();
    link.remove();
  }

  async function handleCopy() {
    const active = $websitesStore.active;
    if (!active) return;
    try {
      await navigator.clipboard.writeText(active.content || '');
      isCopied = true;
      if (copyTimeout) clearTimeout(copyTimeout);
      copyTimeout = setTimeout(() => {
        isCopied = false;
        copyTimeout = null;
      }, 1500);
    } catch (error) {
      console.error('Failed to copy website content:', error);
    }
  }

  async function handleDelete() {
    const active = $websitesStore.active;
    if (!active) return;
    const response = await fetch(`/api/websites/${active.id}`, {
      method: 'DELETE'
    });
    if (!response.ok) {
      console.error('Failed to delete website');
      return;
    }
    await websitesStore.load();
    websitesStore.clearActive();
    isDeleteDialogOpen = false;
  }

  function handleClose() {
    websitesStore.clearActive();
  }

  $: if (isRenameDialogOpen) {
    tick().then(() => {
      renameInput?.focus();
      renameInput?.select();
    });
  }
</script>

<AlertDialog.Root bind:open={isRenameDialogOpen}>
  <AlertDialog.Content
    onOpenAutoFocus={(event) => {
      event.preventDefault();
      renameInput?.focus();
      renameInput?.select();
    }}
  >
    <AlertDialog.Header>
      <AlertDialog.Title>Rename website</AlertDialog.Title>
      <AlertDialog.Description>Update the website title.</AlertDialog.Description>
    </AlertDialog.Header>
    <div class="py-2">
      <input
        class="w-full rounded-md border bg-background px-3 py-2 text-sm shadow-sm outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
        type="text"
        placeholder="Website title"
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
  itemType="website"
  itemName={$websitesStore.active?.title ?? ''}
  onConfirm={handleDelete}
  onCancel={() => (isDeleteDialogOpen = false)}
/>

<div class="website-pane">
  <div class="website-header">
    {#if $websitesStore.active}
      <div class="website-meta">
        <div class="title-row">
          <Globe size={18} />
          <span class="title-text">{$websitesStore.active.title}</span>
        </div>
        <div class="website-meta-row">
          <span class="subtitle">
            <a class="source" href={$websitesStore.active.url} target="_blank" rel="noopener noreferrer">
              <span>{formatDomain($websitesStore.active.domain)}</span>
            </a>
            {#if $websitesStore.active.published_at}
              <span class="pipe">|</span>
              <span class="published-date">
                {formatDateWithOrdinal(new Date($websitesStore.active.published_at))}
              </span>
            {/if}
          </span>
          <div class="website-actions">
          <Button
            size="icon"
            variant="ghost"
            onclick={handlePinToggle}
            aria-label="Pin website"
            title="Pin website"
          >
            {#if $websitesStore.active.pinned}
              <PinOff size={16} />
            {:else}
              <Pin size={16} />
            {/if}
          </Button>
          <Button
            size="icon"
            variant="ghost"
            onclick={openRenameDialog}
            aria-label="Rename website"
            title="Rename website"
          >
            <Pencil size={16} />
          </Button>
          <Button
            size="icon"
            variant="ghost"
            onclick={handleCopy}
            aria-label={isCopied ? 'Copied website' : 'Copy website'}
            title={isCopied ? 'Copied' : 'Copy website'}
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
            aria-label="Download website"
            title="Download website"
          >
            <Download size={16} />
          </Button>
          <Button
            size="icon"
            variant="ghost"
            onclick={handleArchive}
            aria-label={$websitesStore.active.archived ? 'Unarchive website' : 'Archive website'}
            title={$websitesStore.active.archived ? 'Unarchive website' : 'Archive website'}
          >
            <Archive size={16} />
          </Button>
          <Button
            size="icon"
            variant="ghost"
            onclick={() => (isDeleteDialogOpen = true)}
            aria-label="Delete website"
            title="Delete website"
          >
            <Trash2 size={16} />
          </Button>
          <Button
            size="icon"
            variant="ghost"
            onclick={handleClose}
            aria-label="Close website"
            title="Close website"
          >
            <X size={16} />
          </Button>
          </div>
        </div>
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
    padding: 0.5rem 1.5rem;
    min-height: 57px;
    border-bottom: 1px solid var(--color-border);
    background-color: var(--color-card);
  }

  .website-meta {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
    width: 100%;
  }

  .title-row {
    display: inline-flex;
    align-items: center;
    gap: 0.75rem;
    flex-wrap: wrap;
  }

  .website-meta-row {
    display: inline-flex;
    align-items: center;
    gap: 0.75rem;
  }

  .subtitle {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    font-size: 0.8rem;
    color: var(--color-muted-foreground);
  }

  .website-actions {
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
  }

  .pipe {
    color: var(--color-muted-foreground);
  }

  .title-text {
    font-size: 1rem;
    font-weight: 600;
    color: var(--color-foreground);
  }

  .published-date {
    color: var(--color-muted-foreground);
  }

  .website-meta .source {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
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

  :global(.website-viewer a) {
    cursor: pointer;
  }

  :global(.website-viewer table) {
    width: 100%;
    border-collapse: collapse;
    margin: 1em 0;
    font-size: 0.95em;
  }

  :global(.website-viewer th),
  :global(.website-viewer td) {
    border: 1px solid var(--color-border);
    padding: 0em 0.75em;
    text-align: left;
    vertical-align: top;
  }

  :global(.website-viewer thead th) {
    background-color: var(--color-muted);
    color: var(--color-foreground);
    font-weight: 600;
  }

  :global(.website-viewer tbody tr:nth-child(even)) {
    background-color: color-mix(in oklab, var(--color-muted) 40%, transparent);
  }
</style>
