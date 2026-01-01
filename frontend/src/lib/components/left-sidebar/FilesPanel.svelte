<script lang="ts">
  import {
    ChevronDown,
    ChevronRight,
    FileChartPie,
    FileText,
    FileSpreadsheet,
    FileMusic,
    FileVideoCamera,
    FileChartLine,
    Image,
    Folder,
    FolderOpen,
    Trash2,
    MoreHorizontal,
    Pencil,
    Pin,
    PinOff,
    Download,
    GripVertical
  } from 'lucide-svelte';
  import { onDestroy, onMount } from 'svelte';
  import { treeStore } from '$lib/stores/tree';
  import { ingestionStore } from '$lib/stores/ingestion';
  import { ingestionAPI } from '$lib/services/api';
  import { ingestionViewerStore } from '$lib/stores/ingestion-viewer';
  import { websitesStore } from '$lib/stores/websites';
  import { editorStore, currentNoteId } from '$lib/stores/editor';
  import { dispatchCacheEvent } from '$lib/utils/cacheEvents';
  import SidebarLoading from '$lib/components/left-sidebar/SidebarLoading.svelte';
  import SidebarEmptyState from '$lib/components/left-sidebar/SidebarEmptyState.svelte';
  import FileTreeNode from '$lib/components/files/FileTreeNode.svelte';
  import IngestionQueue from '$lib/components/files/IngestionQueue.svelte';
  import TextInputDialog from '$lib/components/left-sidebar/dialogs/TextInputDialog.svelte';
  import DeleteDialogController from '$lib/components/files/DeleteDialogController.svelte';
  import * as Collapsible from '$lib/components/ui/collapsible/index.js';
  import type { IngestionListItem } from '$lib/types/ingestion';

  const basePath = 'documents';

  $: treeData = $treeStore.trees[basePath];
  $: children = treeData?.children || [];
  $: searchQuery = treeData?.searchQuery || '';
  // Show loading if explicitly loading OR if tree hasn't been initialized yet OR if ingestion is loading
  $: loading = (treeData?.loading ?? !treeData) || $ingestionStore.loading;
  $: normalizedQuery = searchQuery.trim().toLowerCase();
  $: processingItems = ($ingestionStore.items || []).filter(
    item => !['ready', 'failed', 'canceled'].includes(item.job.status || '')
  );
  $: failedItems = ($ingestionStore.items || []).filter(
    item => item.job.status === 'failed'
  );
  $: readyItems = ($ingestionStore.items || []).filter(
    item => item.job.status === 'ready' && item.recommended_viewer
  );
  $: filteredProcessingItems = normalizedQuery
    ? processingItems.filter(item =>
        (item.file.filename_original || '').toLowerCase().includes(normalizedQuery)
      )
    : processingItems;
  $: filteredFailedItems = normalizedQuery
    ? failedItems.filter(item =>
        (item.file.filename_original || '').toLowerCase().includes(normalizedQuery)
      )
    : failedItems;
  $: filteredReadyItems = normalizedQuery
    ? readyItems.filter(item =>
        (item.file.filename_original || '').toLowerCase().includes(normalizedQuery)
      )
    : readyItems;
  $: pinnedItems = filteredReadyItems.filter(item => item.file.pinned);
  $: pinnedItemsSorted = [...pinnedItems].sort((a, b) => {
    const aOrder = typeof a.file.pinned_order === 'number' ? a.file.pinned_order : Number.POSITIVE_INFINITY;
    const bOrder = typeof b.file.pinned_order === 'number' ? b.file.pinned_order : Number.POSITIVE_INFINITY;
    if (aOrder !== bOrder) return aOrder - bOrder;
    return (a.file.created_at || '').localeCompare(b.file.created_at || '');
  });
  $: unpinnedReadyItems = filteredReadyItems.filter(item => !item.file.pinned);
  const categoryOrder = [
    'audio',
    'documents',
    'images',
    'presentations',
    'reports',
    'spreadsheets',
    'video',
    'other'
  ];
  const categoryLabels: Record<string, string> = {
    images: 'Images',
    documents: 'Documents',
    spreadsheets: 'Spreadsheets',
    presentations: 'Presentations',
    reports: 'Reports',
    audio: 'Audio',
    video: 'Video',
    other: 'Other'
  };
  function iconForCategory(category: string | null | undefined) {
    if (category === 'images') return Image;
    if (category === 'spreadsheets') return FileSpreadsheet;
    if (category === 'presentations') return FileChartPie;
    if (category === 'reports') return FileChartLine;
    if (category === 'audio') return FileMusic;
    if (category === 'video') return FileVideoCamera;
    return FileText;
  }
  $: categorizedItems = unpinnedReadyItems.reduce<Record<string, IngestionListItem[]>>((acc, item) => {
    const category = item.file.category || 'other';
    if (!acc[category]) acc[category] = [];
    acc[category].push(item);
    return acc;
  }, {});

  $: showPinnedSection = !searchQuery || pinnedItems.length > 0;
  let expandedCategories = new Set<string>();
  let openMenuKey: string | null = null;
  let isRenameOpen = false;
  let renameValue = '';
  let renameItem: IngestionListItem | null = null;
  let isRenaming = false;
  let deleteDialog: { openDialog: (name: string) => void } | null = null;
  let deleteItem: IngestionListItem | null = null;
  const PINNED_DROP_END = '__end__';
  let draggingPinnedId: string | null = null;
  let dragOverPinnedId: string | null = null;

  function openViewer(item: IngestionListItem) {
    if (!item.recommended_viewer) return;
    websitesStore.clearActive();
    editorStore.reset();
    currentNoteId.set(null);
    ingestionViewerStore.open(item.file.id);
  }

  function requestDelete(item: IngestionListItem, event?: MouseEvent) {
    event?.stopPropagation();
    deleteItem = item;
    deleteDialog?.openDialog(item.file.filename_original ?? 'file');
    openMenuKey = null;
  }

  async function confirmDelete(): Promise<boolean> {
    if (!deleteItem) return false;
    const fileId = deleteItem.file.id;
    try {
      await ingestionAPI.delete(fileId);
      if (ingestionViewerStore && $ingestionViewerStore?.active?.file.id === fileId) {
        ingestionViewerStore.clearActive();
      }
      dispatchCacheEvent('file.deleted');
      ingestionStore.removeItem(fileId);
      return true;
    } catch (error) {
      console.error('Failed to delete ingestion:', error);
      return false;
    } finally {
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

  function handlePinnedDragStart(event: DragEvent, fileId: string) {
    draggingPinnedId = fileId;
    dragOverPinnedId = null;
    event.dataTransfer?.setData('text/plain', fileId);
    event.dataTransfer!.effectAllowed = 'move';
  }

  function handlePinnedDragOver(event: DragEvent, fileId: string) {
    if (!draggingPinnedId) return;
    event.preventDefault();
    dragOverPinnedId = fileId;
  }

  async function handlePinnedDrop(event: DragEvent, targetId: string) {
    if (!draggingPinnedId) return;
    event.preventDefault();
    const sourceId = draggingPinnedId;
    draggingPinnedId = null;
    dragOverPinnedId = null;
    if (sourceId === targetId) return;
    const order = pinnedItemsSorted.map(item => item.file.id);
    const fromIndex = order.indexOf(sourceId);
    const toIndex = order.indexOf(targetId);
    if (fromIndex === -1 || toIndex === -1) return;
    const nextOrder = [...order];
    nextOrder.splice(toIndex, 0, nextOrder.splice(fromIndex, 1)[0]);
    ingestionStore.setPinnedOrder(nextOrder);
    try {
      await ingestionAPI.updatePinnedOrder(nextOrder);
    } catch (error) {
      console.error('Failed to update pinned order:', error);
    }
  }

  async function handlePinnedDropEnd(event: DragEvent) {
    if (!draggingPinnedId) return;
    event.preventDefault();
    const sourceId = draggingPinnedId;
    draggingPinnedId = null;
    dragOverPinnedId = null;
    const order = pinnedItemsSorted.map(item => item.file.id);
    const fromIndex = order.indexOf(sourceId);
    if (fromIndex === -1) return;
    const nextOrder = [...order];
    nextOrder.push(nextOrder.splice(fromIndex, 1)[0]);
    ingestionStore.setPinnedOrder(nextOrder);
    try {
      await ingestionAPI.updatePinnedOrder(nextOrder);
    } catch (error) {
      console.error('Failed to update pinned order:', error);
    }
  }

  function handlePinnedDragEnd() {
    draggingPinnedId = null;
    dragOverPinnedId = null;
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

<DeleteDialogController
  bind:this={deleteDialog}
  itemType="file"
  onConfirm={confirmDelete}
/>

{#if loading}
  <SidebarLoading message="Loading files..." />
{:else if treeData?.error}
  <SidebarEmptyState
    icon={Folder}
    title="Service unavailable"
    subtitle="Please try again later."
  />
{:else if children.length === 0 && filteredProcessingItems.length === 0 && filteredFailedItems.length === 0 && filteredReadyItems.length === 0}
  <SidebarEmptyState
    icon={Folder}
    title="No files yet"
    subtitle="Upload or create a file to get started."
  />
{:else}
  <div class="workspace-list">
    <div class="workspace-main">
      {#if showPinnedSection}
        <div class="files-block">
          <div class="files-block-title">Pinned</div>
          {#if pinnedItemsSorted.length > 0}
            <div class="files-block-list">
              {#each pinnedItemsSorted as item (item.file.id)}
                <div
                  class="ingested-row"
                  class:drag-over={dragOverPinnedId === item.file.id}
                  data-ingested-menu-root={`pinned-${item.file.id}`}
                  role="listitem"
                  aria-label={`Pinned file ${stripExtension(item.file.filename_original)}`}
                  ondragover={(event) => handlePinnedDragOver(event, item.file.id)}
                  ondrop={(event) => handlePinnedDrop(event, item.file.id)}
                >
                  <button class="ingested-item ingested-item--file" onclick={() => openViewer(item)}>
                    <span class="ingested-icon">
                      <svelte:component this={iconForCategory(item.file.category)} size={16} />
                    </span>
                    <span class="ingested-name">{stripExtension(item.file.filename_original)}</span>
                  </button>
                  <button
                    class="grab-handle"
                    draggable="true"
                    ondragstart={(event) => handlePinnedDragStart(event, item.file.id)}
                    ondragend={handlePinnedDragEnd}
                    onclick={(event) => event.stopPropagation()}
                    aria-label="Reorder pinned file"
                  >
                    <GripVertical size={14} />
                  </button>
                  <button
                    class="ingested-menu"
                    onclick={(event) => toggleMenu(event, `pinned-${item.file.id}`)}
                    aria-label="File actions"
                  >
                    <MoreHorizontal size={16} />
                  </button>
                  {#if openMenuKey === `pinned-${item.file.id}`}
                    <div class="ingested-menu-dropdown">
                      <button class="menu-item" onclick={() => handleRename(item)}>
                        <Pencil size={16} />
                        <span>Rename</span>
                      </button>
                      <button class="menu-item" onclick={() => handlePinToggle(item)}>
                        {#if item.file.pinned}
                          <PinOff size={16} />
                          <span>Unpin</span>
                        {:else}
                          <Pin size={16} />
                          <span>Pin</span>
                        {/if}
                      </button>
                      <button class="menu-item" onclick={() => handleDownload(item)}>
                        <Download size={16} />
                        <span>Download</span>
                      </button>
                      <button class="menu-item" onclick={(event) => handleDelete(item, event)}>
                        <Trash2 size={16} />
                        <span>Delete</span>
                      </button>
                    </div>
                  {/if}
                </div>
              {/each}
              <div
                class="pinned-drop-zone"
                class:drag-over={dragOverPinnedId === PINNED_DROP_END}
                role="separator"
                aria-label="Drop pinned file at end"
                ondragover={(event) => handlePinnedDragOver(event, PINNED_DROP_END)}
                ondrop={handlePinnedDropEnd}
              ></div>
            </div>
          {:else}
            <div class="files-empty">No pinned files</div>
          {/if}
        </div>
      {/if}
      <div class="files-block">
        {#if !searchQuery}
          <div class="files-block-title">Files</div>
        {/if}
        {#if searchQuery}
          {#each categoryOrder as category}
            {#if categorizedItems[category]?.length}
              <div class="files-block-subtitle">{categoryLabels[category] ?? 'Files'}</div>
              <div class="files-block-list">
                {#each categorizedItems[category] as item (item.file.id)}
                  <div class="ingested-row" data-ingested-menu-root={`files-${item.file.id}`}>
                    <button class="ingested-item ingested-item--file" onclick={() => openViewer(item)}>
                      <span class="ingested-icon">
                        <svelte:component this={iconForCategory(category)} size={16} />
                      </span>
                      <span class="ingested-name">{stripExtension(item.file.filename_original)}</span>
                    </button>
                    <button
                      class="ingested-menu"
                      onclick={(event) => toggleMenu(event, `files-${item.file.id}`)}
                      aria-label="File actions"
                    >
                      <MoreHorizontal size={16} />
                    </button>
                    {#if openMenuKey === `files-${item.file.id}`}
                      <div class="ingested-menu-dropdown">
                        <button class="menu-item" onclick={() => handleRename(item)}>
                          <Pencil size={16} />
                          <span>Rename</span>
                        </button>
                        <button class="menu-item" onclick={() => handlePinToggle(item)}>
                          {#if item.file.pinned}
                            <PinOff size={16} />
                            <span>Unpin</span>
                          {:else}
                            <Pin size={16} />
                            <span>Pin</span>
                          {/if}
                        </button>
                        <button class="menu-item" onclick={() => handleDownload(item)}>
                          <Download size={16} />
                          <span>Download</span>
                        </button>
                        <button class="menu-item" onclick={(event) => handleDelete(item, event)}>
                          <Trash2 size={16} />
                          <span>Delete</span>
                        </button>
                      </div>
                    {/if}
                  </div>
                {/each}
              </div>
            {/if}
          {/each}
        {:else}
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
                        <svelte:component this={iconForCategory(category)} size={16} />
                      </span>
                      <span class="ingested-name">{stripExtension(item.file.filename_original)}</span>
                    </button>
                    <button
                      class="ingested-menu"
                      onclick={(event) => toggleMenu(event, `files-${item.file.id}`)}
                      aria-label="File actions"
                    >
                      <MoreHorizontal size={16} />
                    </button>
                    {#if openMenuKey === `files-${item.file.id}`}
                      <div class="ingested-menu-dropdown">
                        <button class="menu-item" onclick={() => handleRename(item)}>
                          <Pencil size={16} />
                          <span>Rename</span>
                        </button>
                        <button class="menu-item" onclick={() => handlePinToggle(item)}>
                          {#if item.file.pinned}
                            <PinOff size={16} />
                            <span>Unpin</span>
                          {:else}
                            <Pin size={16} />
                            <span>Pin</span>
                          {/if}
                        </button>
                        <button class="menu-item" onclick={() => handleDownload(item)}>
                          <Download size={16} />
                          <span>Download</span>
                        </button>
                        <button class="menu-item" onclick={(event) => handleDelete(item, event)}>
                          <Trash2 size={16} />
                          <span>Delete</span>
                        </button>
                      </div>
                    {/if}
                  </div>
                {/each}
              {/if}
            {/if}
          {/each}
        {/if}
        {#if searchQuery && filteredReadyItems.length === 0}
          <div class="files-empty">No matching files</div>
        {:else if !searchQuery && filteredReadyItems.length === 0}
          <div class="files-empty">No files yet</div>
        {/if}
      </div>
    </div>
    {#if filteredProcessingItems.length > 0}
      <div class="workspace-uploads uploads-block">
        <IngestionQueue items={filteredProcessingItems} />
      </div>
    {/if}
    {#if filteredFailedItems.length > 0}
      <div class="workspace-uploads uploads-block">
        <div class="workspace-results-label">Failed uploads</div>
        {#each filteredFailedItems as item (item.file.id)}
          <div class="failed-item">
            <div class="failed-header">
              <div class="failed-name">{item.file.filename_original}</div>
              <div class="failed-actions">
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
              {item.job.user_message || item.job.error_message || 'Upload failed.'}
              <span class="failed-status">Re-upload to try again.</span>
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
              <span class="archive-chevron transition-transform group-data-[state=open]/collapsible:rotate-90">
                <ChevronRight size={16} />
              </span>
            </Collapsible.Trigger>
            <Collapsible.Content data-slot="collapsible-content" class="archive-content pt-1">
              <div data-slot="sidebar-group-content" data-sidebar="group-content" class="w-full text-sm">
                {#each readyItems as item (item.file.id)}
                  <div class="ingested-row" data-ingested-menu-root={`recent-${item.file.id}`}>
                    <button class="ingested-item ingested-item--file" onclick={() => openViewer(item)}>
                      <span class="ingested-icon">
                        <svelte:component this={iconForCategory(item.file.category)} size={16} />
                      </span>
                      <span class="ingested-name">{stripExtension(item.file.filename_original)}</span>
                    </button>
                    <button
                      class="ingested-menu"
                      onclick={(event) => toggleMenu(event, `recent-${item.file.id}`)}
                      aria-label="File actions"
                    >
                      <MoreHorizontal size={16} />
                    </button>
                    {#if openMenuKey === `recent-${item.file.id}`}
                      <div class="ingested-menu-dropdown">
                        <button class="menu-item" onclick={() => handleRename(item)}>
                          <Pencil size={16} />
                          <span>Rename</span>
                        </button>
                        <button class="menu-item" onclick={() => handlePinToggle(item)}>
                          {#if item.file.pinned}
                            <PinOff size={16} />
                            <span>Unpin</span>
                          {:else}
                            <Pin size={16} />
                            <span>Pin</span>
                          {/if}
                        </button>
                        <button class="menu-item" onclick={() => handleDownload(item)}>
                          <Download size={16} />
                          <span>Download</span>
                        </button>
                        <button class="menu-item" onclick={(event) => handleDelete(item, event)}>
                          <Trash2 size={16} />
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
    gap: 1rem;
    padding-top: 0.5rem;
    min-height: 0;
    flex: 1;
  }

  .workspace-main {
    display: flex;
    flex-direction: column;
    gap: 1rem;
    min-height: 0;
    flex: 1;
  }

  .files-block {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .files-block-list {
    display: flex;
    flex-direction: column;
  }

  .files-block-title {
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--color-muted-foreground);
    font-weight: 600;
    padding: 0 0.25rem;
  }

  .files-block-subtitle {
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--color-muted-foreground);
    font-weight: 600;
    padding: 0.35rem 0.25rem 0.15rem;
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

  .ingested-row.drag-over {
    background: none;
  }

  .ingested-row.drag-over::before {
    content: '';
    position: absolute;
    left: 0.5rem;
    right: 0.5rem;
    top: 0;
    height: 2px;
    border-radius: 999px;
    background: var(--color-sidebar-border);
  }

  .pinned-drop-zone {
    position: relative;
    height: 12px;
  }

  .pinned-drop-zone.drag-over::before {
    content: '';
    position: absolute;
    left: 0.5rem;
    right: 0.5rem;
    bottom: 0;
    height: 2px;
    border-radius: 999px;
    background: var(--color-sidebar-border);
  }

  .grab-handle {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 0.25rem;
    border: none;
    background: none;
    color: var(--color-muted-foreground);
    cursor: grab;
    border-radius: 0.375rem;
    opacity: 0;
    pointer-events: none;
    transition: opacity 0.2s ease;
  }

  .grab-handle:active {
    cursor: grabbing;
  }

  .ingested-row:hover .grab-handle {
    opacity: 0.9;
    pointer-events: auto;
  }

  .ingested-row--nested {
    padding-left: 1rem;
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
    align-items: center;
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
    margin-left: 1rem;
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
    font-size: 0.875rem;
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

  .uploads-block {
    margin-top: auto;
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
    max-height: min(80vh, 720px);
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
