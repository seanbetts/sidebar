<script lang="ts">
  import { Folder } from 'lucide-svelte';
  import { filesStore } from '$lib/stores/files';
  import SidebarLoading from '$lib/components/left-sidebar/SidebarLoading.svelte';
  import SidebarEmptyState from '$lib/components/left-sidebar/SidebarEmptyState.svelte';
  import FileTreeNode from '$lib/components/files/FileTreeNode.svelte';
  import type { FileNode } from '$lib/types/file';

  const basePath = '.';

  $: treeData = $filesStore.trees[basePath];
  $: children = treeData?.children || [];
  $: searchQuery = treeData?.searchQuery || '';
  // Show loading if explicitly loading OR if tree hasn't been initialized yet
  $: loading = treeData?.loading ?? !treeData;

  // Data loading is now handled by parent Sidebar component
  // onMount removed to prevent duplicate loads and initial flicker

  function handleToggle(path: string) {
    filesStore.toggleExpanded(basePath, path);
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
{:else if children.length === 0}
  <SidebarEmptyState
    icon={Folder}
    title="No files yet"
    subtitle="Upload or create a file to get started."
  />
{:else}
  <div class="workspace-list">
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

  /* Empty state handled by SidebarEmptyState */
</style>
