<script lang="ts">
  import { ChevronDown, ChevronRight, Image, Folder, FolderOpen, RotateCcw, Trash2 } from 'lucide-svelte';
  import { onDestroy, onMount } from 'svelte';
  import { treeStore } from '$lib/stores/tree';
  import { ingestionStore } from '$lib/stores/ingestion';
  import { ingestionAPI } from '$lib/services/api';
  import { ingestionViewerStore } from '$lib/stores/ingestion-viewer';
  import SidebarLoading from '$lib/components/left-sidebar/SidebarLoading.svelte';
  import SidebarEmptyState from '$lib/components/left-sidebar/SidebarEmptyState.svelte';
  import FileTreeNode from '$lib/components/files/FileTreeNode.svelte';
  import IngestionQueue from '$lib/components/files/IngestionQueue.svelte';
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
  $: readyItems = ($ingestionStore.items || []).filter(
    item => item.job.status === 'ready' && item.recommended_viewer
  );
  $: pinnedItems = readyItems.filter(item => item.file.pinned);
  $: imageItems = readyItems.filter(item => item.file.category === 'images');
  let retryingIds = new Set<string>();
  let imagesExpanded = false;

  function openViewer(item: IngestionListItem) {
    if (!item.recommended_viewer) return;
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

  async function deleteIngestion(fileId: string) {
    try {
      await ingestionAPI.delete(fileId);
      await ingestionStore.load();
    } catch (error) {
      console.error('Failed to delete ingestion:', error);
    }
  }

  onMount(() => {
    ingestionStore.startPolling();
  });

  onDestroy(() => {
    ingestionStore.stopPolling();
  });

  // Data loading is now handled by parent Sidebar component
  // onMount removed to prevent duplicate loads and initial flicker

  function handleToggle(path: string) {
    treeStore.toggleExpanded(basePath, path);
  }

  function toggleImages() {
    imagesExpanded = !imagesExpanded;
  }

  function stripExtension(name: string): string {
    const index = name.lastIndexOf('.');
    if (index <= 0) return name;
    return name.slice(0, index);
  }

</script>

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
          {#each pinnedItems as item (item.file.id)}
            <button class="ingested-item" onclick={() => openViewer(item)}>
              <span class="ingested-name">{item.file.filename_original}</span>
              <span class="ingested-action">Open</span>
            </button>
          {/each}
        {:else}
          <div class="files-empty">No pinned files</div>
        {/if}
      </div>
      {#if processingItems.length > 0}
        <IngestionQueue items={processingItems} />
      {/if}
      {#if failedItems.length > 0}
        <div class="workspace-results-label">Failed uploads</div>
        {#each failedItems as item (item.file.id)}
          <div class="failed-item">
            <div class="failed-header">
              <div class="failed-name">{item.file.filename_original}</div>
              <div class="failed-actions">
                <button
                  class="failed-action"
                  type="button"
                  onclick={() => retryIngestion(item.file.id)}
                  aria-label="Retry upload"
                  disabled={retryingIds.has(item.file.id)}
                >
                  <RotateCcw size={14} />
                </button>
                <button
                  class="failed-action"
                  type="button"
                  onclick={() => deleteIngestion(item.file.id)}
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
      {/if}
      <div class="files-block">
        <div class="files-block-title">Files</div>
        {#if searchQuery}
          <div class="workspace-results-label">Results</div>
        {/if}
      {#if imageItems.length > 0}
        <div class="tree-node">
          <div class="node-content">
            <button class="node-button expandable" onclick={toggleImages}>
              <span class="chevron">
                {#if imagesExpanded}
                  <ChevronDown size={16} />
                {:else}
                  <ChevronRight size={16} />
                {/if}
              </span>
              <span class="icon">
                {#if imagesExpanded}
                  <FolderOpen size={16} />
                {:else}
                  <Folder size={16} />
                {/if}
              </span>
              <span class="name">Images</span>
            </button>
          </div>
        </div>
        {#if imagesExpanded}
          {#each imageItems as item (item.file.id)}
            <button class="ingested-item ingested-item--nested" onclick={() => openViewer(item)}>
              <span class="ingested-icon">
                <Image size={16} />
              </span>
              <span class="ingested-name">{stripExtension(item.file.filename_original)}</span>
              <span class="ingested-action">Open</span>
            </button>
          {/each}
        {/if}
        {/if}
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
        {:else if imageItems.length === 0}
          <div class="files-empty">No files yet</div>
        {/if}
      </div>
    </div>
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
                  <button class="ingested-item" onclick={() => openViewer(item)}>
                    <span class="ingested-name">{item.file.filename_original}</span>
                    <span class="ingested-action">Open</span>
                  </button>
                {/each}
              </div>
            </Collapsible.Content>
          </div>
        </Collapsible.Root>
      </div>
    {/if}
  </div>
{/if}

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
  }

  .ingested-action {
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--color-muted-foreground);
  }

  .ingested-item--nested {
    margin-left: 1.6rem;
    justify-content: flex-start;
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

  .ingested-item--nested .ingested-name {
    font-size: 0.875rem;
  }

  .ingested-item--nested .ingested-action {
    margin-left: auto;
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
