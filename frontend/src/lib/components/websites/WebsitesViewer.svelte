<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { Editor } from '@tiptap/core';
  import StarterKit from '@tiptap/starter-kit';
  import { Image } from '@tiptap/extension-image';
  import { TaskList, TaskItem } from '@tiptap/extension-list';
  import { TableKit } from '@tiptap/extension-table';
  import { Markdown } from 'tiptap-markdown';
  import { websitesStore } from '$lib/stores/websites';
  import DeleteDialogController from '$lib/components/files/DeleteDialogController.svelte';
  import WebsiteHeader from '$lib/components/websites/WebsiteHeader.svelte';
  import WebsiteRenameDialog from '$lib/components/websites/WebsiteRenameDialog.svelte';
  import { dispatchCacheEvent } from '$lib/utils/cacheEvents';

  let editorElement: HTMLDivElement;
  let editor: Editor | null = null;
  let isRenameDialogOpen = false;
  let renameValue = '';
  let deleteDialog: { openDialog: (name: string) => void } | null = null;
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
    websitesStore.renameLocal?.(active.id, trimmed);
    websitesStore.updateActiveLocal?.({ title: trimmed });
    dispatchCacheEvent('website.renamed');
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
    websitesStore.setPinnedLocal?.(active.id, !active.pinned);
    websitesStore.updateActiveLocal?.({ pinned: !active.pinned });
    dispatchCacheEvent('website.pinned');
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
    const nextArchived = !active.archived;
    websitesStore.setArchivedLocal?.(active.id, nextArchived);
    dispatchCacheEvent('website.archived');
    if (nextArchived) {
      websitesStore.clearActive();
    } else {
      websitesStore.updateActiveLocal?.({ archived: nextArchived });
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

  async function handleDelete(): Promise<boolean> {
    const active = $websitesStore.active;
    if (!active) return false;
    const response = await fetch(`/api/websites/${active.id}`, {
      method: 'DELETE'
    });
    if (!response.ok) {
      console.error('Failed to delete website');
      return false;
    }
    websitesStore.removeLocal?.(active.id);
    websitesStore.clearActive();
    dispatchCacheEvent('website.deleted');
    // dialog closes via controller
    return true;
  }

  function requestDelete() {
    const active = $websitesStore.active;
    if (!active) return;
    deleteDialog?.openDialog(active.title || 'website');
  }

  function handleClose() {
    websitesStore.clearActive();
  }

</script>

<WebsiteRenameDialog
  bind:open={isRenameDialogOpen}
  bind:value={renameValue}
  onConfirm={handleRename}
  onCancel={() => (isRenameDialogOpen = false)}
/>

<DeleteDialogController
  bind:this={deleteDialog}
  itemType="website"
  onConfirm={handleDelete}
/>

<div class="website-pane">
  <WebsiteHeader
    website={$websitesStore.active}
    {isCopied}
    {formatDomain}
    formatDate={formatDateWithOrdinal}
    onPinToggle={handlePinToggle}
    onRename={openRenameDialog}
    onCopy={handleCopy}
    onDownload={handleDownload}
    onArchive={handleArchive}
    onDelete={requestDelete}
    onClose={handleClose}
  />
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
