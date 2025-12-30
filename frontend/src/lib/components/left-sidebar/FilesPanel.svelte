<script lang="ts">
  import { Folder, RotateCcw, Trash2 } from 'lucide-svelte';
  import { onDestroy, onMount } from 'svelte';
  import { treeStore } from '$lib/stores/tree';
  import { ingestionStore } from '$lib/stores/ingestion';
  import { ingestionAPI } from '$lib/services/api';
  import { ingestionViewerStore } from '$lib/stores/ingestion-viewer';
  import SidebarLoading from '$lib/components/left-sidebar/SidebarLoading.svelte';
  import SidebarEmptyState from '$lib/components/left-sidebar/SidebarEmptyState.svelte';
  import FileTreeNode from '$lib/components/files/FileTreeNode.svelte';
  import IngestionQueue from '$lib/components/files/IngestionQueue.svelte';
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
    item => item.job.status === 'ready'
  );
  let retryingIds = new Set<string>();

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

</script>

{#if loading}
  <SidebarLoading message="Loading files..." />
{:else if treeData?.error}
  <SidebarEmptyState
    icon={Folder}
    title="Service unavailable"
    subtitle="Please try again later."
  />
{:else if children.length === 0 && processingItems.length === 0}
  <SidebarEmptyState
    icon={Folder}
    title="No files yet"
    subtitle="Upload or create a file to get started."
  />
{:else}
  <div class="workspace-list">
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
    {#if readyItems.length > 0}
      <div class="workspace-results-label">Recent uploads</div>
      {#each readyItems as item (item.file.id)}
        <button
          class="ingested-item"
          onclick={() => openViewer(item)}
          disabled={!item.recommended_viewer}
        >
          <span class="ingested-name">{item.file.filename_original}</span>
          <span class="ingested-action">{item.recommended_viewer ? 'Open' : 'Unavailable'}</span>
        </button>
      {/each}
    {/if}
    {#if searchQuery}
      <div class="workspace-results-label">Results</div>
    {/if}
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
  </div>
{/if}

<style>
  .workspace-list {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    padding: 0.25rem 0;
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
