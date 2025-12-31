<script lang="ts">
  import {
    ChevronDown,
    ChevronRight,
    FileText,
    Image,
    Folder,
    FolderOpen,
    RotateCcw,
    Trash2,
    MoreHorizontal,
    Pencil,
    Pin,
    PinOff,
    Download
  } from 'lucide-svelte';
  import { onDestroy, onMount } from 'svelte';
  import { treeStore } from '$lib/stores/tree';
  import { ingestionStore } from '$lib/stores/ingestion';
  import { ingestionAPI } from '$lib/services/api';
  import { ingestionViewerStore } from '$lib/stores/ingestion-viewer';
  import { websitesStore } from '$lib/stores/websites';
  import { editorStore, currentNoteId } from '$lib/stores/editor';
  import SidebarLoading from '$lib/components/left-sidebar/SidebarLoading.svelte';
  import SidebarEmptyState from '$lib/components/left-sidebar/SidebarEmptyState.svelte';
  import FileTreeNode from '$lib/components/files/FileTreeNode.svelte';
  import IngestionQueue from '$lib/components/files/IngestionQueue.svelte';
  import TextInputDialog from '$lib/components/left-sidebar/dialogs/TextInputDialog.svelte';
  import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';
  import { buttonVariants } from '$lib/components/ui/button/index.js';
  import * as Collapsible from '$lib/components/ui/collapsible/index.js';
  import type { FileNode } from '$lib/types/file';
  import type { IngestionListItem } from '$lib/types/ingestion';

  const basePath = '.';

  $: treeData = $treeStore.trees[basePath];
  $: children = treeData?.children || [];
  $: searchQuery = treeData?.searchQuery || '';
  // Show loading if explicitly loading OR if tree hasn't been initialized yet
  $: loading = treeData?.loading ?? !treeData;
  $: processingItems = ($ingestionStore.items || []).filter(
    item => !['ready', 'failed', 'canceled'].includes(item.job.status || '')
  );
  $: failedItems = ($ingestionStore.items || []).filter(
    item => item.job.status === 'failed'
  );
  const nonRetryableErrors = new Set(['UNSUPPORTED_TYPE', 'FILE_EMPTY', 'SOURCE_MISSING']);
  $: readyItems = ($ingestionStore.items || []).filter(
    item => item.job.status === 'ready' && item.recommended_viewer
  );
  $: pinnedItems = readyItems.filter(item => item.file.pinned);
  const categoryOrder = [
    'images',
    'pdf',
    'documents',
    'spreadsheets',
    'presentations',
    'audio',
    'video',
    'other'
  ];
  const categoryLabels: Record<string, string> = {
    images: 'Images',
    pdf: 'PDFs',
    documents: 'Documents',
    spreadsheets: 'Spreadsheets',
    presentations: 'Presentations',
    audio: 'Audio',
    video: 'Video',
    other: 'Other'
  };
  $: categorizedItems = readyItems.reduce<Record<string, IngestionListItem[]>>((acc, item) => {
    const category = item.file.category || 'other';
    if (!acc[category]) acc[category] = [];
    acc[category].push(item);
    return acc;
  }, {});
  let retryingIds = new Set<string>();
  let expandedCategories = new Set<string>();
  let openMenuKey: string | null = null;
  let isRenameOpen = false;
  let renameValue = '';
  let renameItem: IngestionListItem | null = null;
  let isRenaming = false;
  let isDeleteDialogOpen = false;
  let deleteItem: IngestionListItem | null = null;
  let deleteButton: HTMLButtonElement | null = null;

  function openViewer(item: IngestionListItem) {
    if (!item.recommended_viewer) return;
    websitesStore.clearActive();
    editorStore.reset();
    currentNoteId.set(null);
    ingestionViewerStore.open(item.file.id);
  }

  async function retryIngestion(fileId: string) {
    retryingIds = new Set(retryingIds).add(fileId);
    try {
      await ingestionAPI.reprocess(fileId);
      await ingestionStore.load();
      ingestionStore.startPolling();
    } catch (error) {
      console.error('Failed to retry ingestion:', error);
    } finally {
      const next = new Set(retryingIds);
      next.delete(fileId);
      retryingIds = next;
    }
  }

  function requestDelete(item: IngestionListItem, event?: MouseEvent) {
    event?.stopPropagation();
    deleteItem = item;
    isDeleteDialogOpen = true;
    openMenuKey = null;
  }

  async function confirmDelete() {
    if (!deleteItem) return;
    const fileId = deleteItem.file.id;
    try {
      await ingestionAPI.delete(fileId);
      if (ingestionViewerStore && $ingestionViewerStore?.active?.file.id === fileId) {
        ingestionViewerStore.clearActive();
      }
      await ingestionStore.load();
    } catch (error) {
      console.error('Failed to delete ingestion:', error);
    } finally {
      isDeleteDialogOpen = false;
      deleteItem = null;
    }
  }

  onMount(() => {
    ingestionStore.startPolling();
    const handleDocumentClick = (event: MouseEvent) => {
      if (!openMenuKey) return;
      const target = event.target as HTMLElement | null;
      const root = target?.closest<HTMLElement>('[data-ingested-menu-root]');
      if (!root || root.dataset.ingestedMenuRoot !== openMenuKey) {
        openMenuKey = null;
      }
    };
    document.addEventListener('click', handleDocumentClick);
    return () => document.removeEventListener('click', handleDocumentClick);
  });

  onDestroy(() => {
    ingestionStore.stopPolling();
  });

  // Data loading is now handled by parent Sidebar component
  // onMount removed to prevent duplicate loads and initial flicker

  function handleToggle(path: string) {
    treeStore.toggleExpanded(basePath, path);
  }

  function toggleCategory(category: string) {
    const next = new Set(expandedCategories);
    if (next.has(category)) {
      next.delete(category);
    } else {
      next.add(category);
    }
    expandedCategories = next;
  }

  function stripExtension(name: string): string {
    const index = name.lastIndexOf('.');
    if (index <= 0) return name;
    return name.slice(0, index);
  }

  function toggleMenu(event: MouseEvent, menuKey: string) {
    event.stopPropagation();
    openMenuKey = openMenuKey === menuKey ? null : menuKey;
  }

  async function handlePinToggle(item: IngestionListItem) {
    try {
      const nextPinned = !item.file.pinned;
      await ingestionAPI.setPinned(item.file.id, nextPinned);
      ingestionStore.updatePinned(item.file.id, nextPinned);
      if (ingestionViewerStore) {
        ingestionViewerStore.updatePinned(item.file.id, nextPinned);
      }
    } catch (error) {
      console.error('Failed to update pin:', error);
    } finally {
      openMenuKey = null;
    }
  }

  async function handleDownload(item: IngestionListItem) {
    if (!item.recommended_viewer) return;
    try {
      const response = await ingestionAPI.getContent(item.file.id, item.recommended_viewer);
      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = item.file.filename_original;
      link.click();
      URL.revokeObjectURL(url);
    } catch (error) {
      console.error('Failed to download file:', error);
    } finally {
      openMenuKey = null;
    }
  }

  function handleDelete(item: IngestionListItem, event?: MouseEvent) {
    requestDelete(item, event);
  }

  async function handleRename(item: IngestionListItem) {
    renameItem = item;
    renameValue = stripExtension(item.file.filename_original);
    isRenameOpen = true;
    openMenuKey = null;
  }

  async function confirmRename() {
    if (!renameItem) return;
    const original = renameItem.file.filename_original;
    const extensionMatch = original.match(/\.[^/.]+$/);
    const extension = extensionMatch ? extensionMatch[0] : '';
    const trimmed = renameValue.trim();
    if (!trimmed) return;
    const filename = extension && !trimmed.endsWith(extension)
      ? `${trimmed}${extension}`
      : trimmed;
    isRenaming = true;
    try {
      await ingestionAPI.rename(renameItem.file.id, filename);
      ingestionStore.updateFilename(renameItem.file.id, filename);
      ingestionViewerStore.updateFilename(renameItem.file.id, filename);
      isRenameOpen = false;
      renameItem = null;
    } catch (error) {
      console.error('Failed to rename ingestion:', error);
    } finally {
      isRenaming = false;
    }
  }

</script>

<AlertDialog.Root bind:open={isDeleteDialogOpen}>
  <AlertDialog.Content
    onOpenAutoFocus={(event) => {
      event.preventDefault();
      deleteButton?.focus();
    }}
  >
    <AlertDialog.Header>
      <AlertDialog.Title>Delete file?</AlertDialog.Title>
      <AlertDialog.Description>
        This will permanently delete "{deleteItem?.file.filename_original}". This action cannot be undone.
      </AlertDialog.Description>
    </AlertDialog.Header>
    <AlertDialog.Footer>
      <AlertDialog.Cancel>Cancel</AlertDialog.Cancel>
      <AlertDialog.Action
        class={buttonVariants({ variant: 'destructive' })}
        bind:ref={deleteButton}
        onclick={confirmDelete}
      >
        Delete
      </AlertDialog.Action>
    </AlertDialog.Footer>
  </AlertDialog.Content>
</AlertDialog.Root>

{#if loading}
  <SidebarLoading message="Loading files..." />
{:else if treeData?.error}
  <SidebarEmptyState
    icon={Folder}
    title="Service unavailable"
    subtitle="Please try again later."
  />
{:else if children.length === 0 && processingItems.length === 0 && failedItems.length === 0 && readyItems.length === 0}
  <SidebarEmptyState
    icon={Folder}
    title="No files yet"
    subtitle="Upload or create a file to get started."
  />
{:else}
  <div class="workspace-list">
    <div class="workspace-main">
      <div class="files-block">
        <div class="files-block-title">Pinned</div>
        {#if pinnedItems.length > 0}
          <div class="files-block-list">
            {#each pinnedItems as item (item.file.id)}
              <div class="ingested-row" data-ingested-menu-root={`pinned-${item.file.id}`}>
                <button class="ingested-item ingested-item--file" onclick={() => openViewer(item)}>
                  <span class="ingested-icon">
                    {#if item.file.category === 'images'}
                      <Image size={16} />
                    {:else}
                      <FileText size={16} />
                    {/if}
                  </span>
                  <span class="ingested-name">{stripExtension(item.file.filename_original)}</span>
                </button>
                <button
                  class="ingested-menu"
                  onclick={(event) => toggleMenu(event, `pinned-${item.file.id}`)}
                  aria-label="File actions"
                >
                  <MoreHorizontal size={14} />
                </button>
                {#if openMenuKey === `pinned-${item.file.id}`}
                  <div class="ingested-menu-dropdown">
                    <button class="menu-item" onclick={() => handleRename(item)}>
                      <Pencil size={14} />
                      <span>Rename</span>
                    </button>
                    <button class="menu-item" onclick={() => handlePinToggle(item)}>
                      {#if item.file.pinned}
                        <PinOff size={14} />
                        <span>Unpin</span>
                      {:else}
                        <Pin size={14} />
                        <span>Pin</span>
                      {/if}
                    </button>
                    <button class="menu-item" onclick={() => handleDownload(item)}>
                      <Download size={14} />
                      <span>Download</span>
                    </button>
                    <button class="menu-item delete" onclick={(event) => handleDelete(item, event)}>
                      <Trash2 size={14} />
                      <span>Delete</span>
                    </button>
                  </div>
                {/if}
              </div>
            {/each}
          </div>
        {:else}
          <div class="files-empty">No pinned files</div>
        {/if}
      </div>
      <div class="files-block">
        <div class="files-block-title">Files</div>
        {#if searchQuery}
          <div class="workspace-results-label">Results</div>
        {/if}
      {#each categoryOrder as category}
        {#if categorizedItems[category]?.length}
          <div class="tree-node">
            <div class="node-content">
              <button class="node-button expandable" onclick={() => toggleCategory(category)}>
                <span class="chevron">
                  {#if expandedCategories.has(category)}
                    <ChevronDown size={16} />
                  {:else}
                    <ChevronRight size={16} />
                  {/if}
                </span>
                <span class="icon">
                  {#if expandedCategories.has(category)}
                    <FolderOpen size={16} />
                  {:else}
                    <Folder size={16} />
                  {/if}
                </span>
                <span class="name">{categoryLabels[category] ?? 'Files'}</span>
              </button>
            </div>
          </div>
          {#if expandedCategories.has(category)}
            {#each categorizedItems[category] as item (item.file.id)}
              <div class="ingested-row ingested-row--nested" data-ingested-menu-root={`files-${item.file.id}`}>
                <button class="ingested-item ingested-item--file ingested-item--nested" onclick={() => openViewer(item)}>
                  <span class="ingested-icon">
                    {#if category === 'images'}
                      <Image size={16} />
                    {:else}
                      <FileText size={16} />
                    {/if}
                  </span>
                  <span class="ingested-name">{stripExtension(item.file.filename_original)}</span>
                </button>
                <button
                  class="ingested-menu"
                  onclick={(event) => toggleMenu(event, `files-${item.file.id}`)}
                  aria-label="File actions"
                >
                  <MoreHorizontal size={14} />
                </button>
                {#if openMenuKey === `files-${item.file.id}`}
                  <div class="ingested-menu-dropdown">
                    <button class="menu-item" onclick={() => handleRename(item)}>
                      <Pencil size={14} />
                      <span>Rename</span>
                    </button>
                    <button class="menu-item" onclick={() => handlePinToggle(item)}>
                      {#if item.file.pinned}
                        <PinOff size={14} />
                        <span>Unpin</span>
                      {:else}
                        <Pin size={14} />
                        <span>Pin</span>
                      {/if}
                    </button>
                    <button class="menu-item" onclick={() => handleDownload(item)}>
                      <Download size={14} />
                      <span>Download</span>
                    </button>
                    <button class="menu-item delete" onclick={(event) => handleDelete(item, event)}>
                      <Trash2 size={14} />
                      <span>Delete</span>
                    </button>
                  </div>
                {/if}
              </div>
            {/each}
          {/if}
        {/if}
      {/each}
        {#if children.length > 0}
          {#each children as node (node.path)}
            <FileTreeNode
              node={node}
              level={0}
              onToggle={handleToggle}
              basePath={basePath}
              hideExtensions={false}
              showActions={true}
            />
          {/each}
        {:else if readyItems.length === 0}
          <div class="files-empty">No files yet</div>
        {/if}
      </div>
    </div>
    {#if processingItems.length > 0}
      <div class="workspace-uploads uploads-block">
        <IngestionQueue items={processingItems} />
      </div>
    {/if}
    {#if failedItems.length > 0}
      <div class="workspace-uploads uploads-block">
        <div class="workspace-results-label">Failed uploads</div>
        {#each failedItems as item (item.file.id)}
          <div class="failed-item">
            <div class="failed-header">
              <div class="failed-name">{item.file.filename_original}</div>
              <div class="failed-actions">
                {#if !nonRetryableErrors.has(item.job.error_code)}
                  <button
                    class="failed-action"
                    type="button"
                    onclick={() => retryIngestion(item.file.id)}
                    aria-label="Retry upload"
                    disabled={retryingIds.has(item.file.id)}
                  >
                    <RotateCcw size={14} />
                  </button>
                {/if}
                <button
                  class="failed-action"
                  type="button"
                  onclick={(event) => handleDelete(item, event)}
                  aria-label="Delete upload"
                >
                  <Trash2 size={14} />
                </button>
              </div>
            </div>
            <div class="failed-message">
              {#if retryingIds.has(item.file.id)}
                <span class="failed-status">Retrying...</span>
              {:else}
                {item.job.user_message || item.job.error_message || 'Upload failed.'}
              {/if}
            </div>
          </div>
        {/each}
      </div>
    {/if}
    {#if readyItems.length > 0}
      <div class="workspace-uploads uploads-block">
        <Collapsible.Root defaultOpen={false} class="group/collapsible" data-collapsible-root>
          <div data-slot="sidebar-group" data-sidebar="group" class="relative flex w-full min-w-0 flex-col p-2">
            <Collapsible.Trigger
              data-slot="sidebar-group-label"
              data-sidebar="group-label"
              class="archive-trigger"
            >
              <span class="uploads-label">Recent uploads</span>
              <ChevronRight class="archive-chevron transition-transform group-data-[state=open]/collapsible:rotate-90" />
            </Collapsible.Trigger>
            <Collapsible.Content data-slot="collapsible-content" class="archive-content pt-1">
              <div data-slot="sidebar-group-content" data-sidebar="group-content" class="w-full text-sm">
                {#each readyItems as item (item.file.id)}
                  <div class="ingested-row" data-ingested-menu-root={`recent-${item.file.id}`}>
                    <button class="ingested-item ingested-item--file" onclick={() => openViewer(item)}>
                      <span class="ingested-icon">
                        {#if item.file.category === 'images'}
                          <Image size={16} />
                        {:else}
                          <FileText size={16} />
                        {/if}
                      </span>
                      <span class="ingested-name">{stripExtension(item.file.filename_original)}</span>
                    </button>
                    <button
                      class="ingested-menu"
                      onclick={(event) => toggleMenu(event, `recent-${item.file.id}`)}
                      aria-label="File actions"
                    >
                      <MoreHorizontal size={14} />
                    </button>
                    {#if openMenuKey === `recent-${item.file.id}`}
                      <div class="ingested-menu-dropdown">
                        <button class="menu-item" onclick={() => handleRename(item)}>
                          <Pencil size={14} />
                          <span>Rename</span>
                        </button>
                        <button class="menu-item" onclick={() => handlePinToggle(item)}>
                          {#if item.file.pinned}
                            <PinOff size={14} />
                            <span>Unpin</span>
                          {:else}
                            <Pin size={14} />
                            <span>Pin</span>
                          {/if}
                        </button>
                        <button class="menu-item" onclick={() => handleDownload(item)}>
                          <Download size={14} />
                          <span>Download</span>
                        </button>
                        <button class="menu-item delete" onclick={(event) => handleDelete(item, event)}>
                          <Trash2 size={14} />
                          <span>Delete</span>
                        </button>
                      </div>
                    {/if}
                  </div>
                {/each}
              </div>
            </Collapsible.Content>
          </div>
        </Collapsible.Root>
      </div>
    {/if}
  </div>
{/if}

<TextInputDialog
  bind:open={isRenameOpen}
  title="Rename file"
  description="Update the file name."
  placeholder="File name"
  bind:value={renameValue}
  confirmLabel="Rename"
  cancelLabel="Cancel"
  busyLabel="Renaming..."
  isBusy={isRenaming}
  onConfirm={confirmRename}
  onCancel={() => {
    isRenameOpen = false;
    renameItem = null;
  }}
/>

<style>
  .workspace-list {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    padding: 0.25rem 0;
    min-height: 0;
    flex: 1;
  }

  .workspace-main {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    min-height: 0;
    flex: 1;
  }

  .files-block {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .files-block-list {
    padding-left: 0.5rem;
  }

  .files-block-title {
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--color-muted-foreground);
    font-weight: 600;
    padding: 0 0.25rem;
  }

  .files-empty {
    padding: 0.5rem 0.25rem;
    color: var(--color-muted-foreground);
    font-size: 0.8rem;
  }

  .workspace-uploads {
    margin-top: auto;
  }

  .workspace-results-label {
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--color-muted-foreground);
    font-weight: 600;
    padding: 0 0.25rem;
  }

  .ingested-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.5rem;
    padding: 0.35rem 0.5rem;
    border: none;
    background: transparent;
    cursor: pointer;
    color: var(--color-foreground);
    text-align: left;
    min-width: 0;
    flex: 1;
  }

  .ingested-item:hover {
    background-color: var(--color-sidebar-accent);
  }

  .ingested-item:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .ingested-name {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    flex: 1;
    min-width: 0;
    max-width: 100%;
  }

  .ingested-row {
    position: relative;
    display: flex;
    align-items: center;
    gap: 0.25rem;
    width: 100%;
  }

  .ingested-row--nested {
    padding-left: 1.6rem;
  }

  .ingested-item--file {
    justify-content: flex-start;
    font-size: 0.875rem;
    min-width: 0;
    overflow: hidden;
  }

  .tree-node {
    user-select: none;
  }

  .node-content {
    display: flex;
    align-items: flex-start;
    gap: 0.5rem;
  }

  .node-button {
    display: flex;
    align-items: center;
    gap: 0.375rem;
    flex: 1;
    padding: 0.375rem 0.5rem;
    background: none;
    border: none;
    cursor: pointer;
    font-size: 0.875rem;
    color: var(--color-sidebar-foreground);
    transition: background-color 0.2s;
    text-align: left;
    min-width: 0;
  }

  .node-content:hover .node-button {
    background-color: var(--color-sidebar-accent);
  }

  .node-button.expandable {
    cursor: pointer;
  }

  .chevron {
    display: flex;
    align-items: center;
    color: var(--color-muted-foreground);
  }

  .icon {
    display: flex;
    align-items: center;
    color: var(--color-sidebar-foreground);
  }

  .name {
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .ingested-icon {
    display: flex;
    align-items: center;
    color: var(--color-muted-foreground);
  }

  .ingested-item--file .ingested-name {
    font-size: 0.875rem;
  }

  .ingested-menu {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0.25rem;
    background: none;
    border: none;
    cursor: pointer;
    border-radius: 0.25rem;
    color: var(--color-muted-foreground);
    opacity: 0;
    align-self: center;
    transition: all 0.2s;
  }

  .ingested-row:hover .ingested-menu {
    opacity: 1;
  }

  .ingested-menu:hover {
    background-color: var(--color-accent);
  }

  .ingested-menu-dropdown {
    position: absolute;
    top: 100%;
    right: 0;
    margin-top: 0.25rem;
    background-color: var(--color-popover);
    border: 1px solid var(--color-border);
    border-radius: 0.375rem;
    box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
    z-index: 9999;
    min-width: 150px;
  }

  .ingested-menu-dropdown .menu-item {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    width: 100%;
    padding: 0.5rem 0.75rem;
    background: none;
    border: none;
    cursor: pointer;
    font-size: 0.8rem;
    text-align: left;
    transition: background-color 0.2s;
    color: var(--color-popover-foreground);
  }

  .ingested-menu-dropdown .menu-item:hover:not(:disabled) {
    background-color: var(--color-accent);
  }

  .ingested-menu-dropdown .menu-item:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .ingested-menu-dropdown .menu-item.delete {
    color: var(--color-destructive);
  }

  .uploads-block {
    margin-top: 0.5rem;
  }

  .uploads-label {
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--color-muted-foreground);
    font-weight: 600;
  }

  :global(.archive-trigger) {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.5rem;
    width: 100%;
    border: none;
    background: none;
    cursor: pointer;
    padding: 0.2rem 0.25rem;
    border-radius: 0.375rem;
    text-align: left;
  }

  :global(.archive-trigger:hover) {
    background-color: var(--color-sidebar-accent);
  }

  .archive-chevron {
    width: 16px;
    height: 16px;
    flex-shrink: 0;
    color: var(--color-muted-foreground);
  }

  :global(.archive-trigger:hover) .archive-chevron,
  :global(.archive-trigger:hover) .uploads-label {
    color: var(--color-foreground);
  }

  :global(.archive-content) {
    max-height: min(40vh, 320px);
    overflow-y: auto;
    padding-right: 0.25rem;
  }

  .failed-item {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    padding: 0.35rem 0.5rem;
    border-radius: 0.4rem;
    background: color-mix(in oklab, var(--color-destructive) 8%, transparent);
  }

  .failed-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.5rem;
  }

  .failed-name {
    font-size: 0.85rem;
    color: var(--color-foreground);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .failed-actions {
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
  }

  .failed-action {
    border: none;
    background: transparent;
    padding: 0;
    cursor: pointer;
    color: var(--color-muted-foreground);
  }

  .failed-action:hover {
    color: var(--color-foreground);
  }

  .failed-action:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .failed-message {
    font-size: 0.75rem;
    color: var(--color-muted-foreground);
  }

  .failed-status {
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.08em;
  }

  /* Empty state handled by SidebarEmptyState */
</style>
