<script lang="ts">
  import { filesStore } from '$lib/stores/files';
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
  <div class="workspace-empty">Loading files...</div>
{:else if children.length === 0}
  <div class="workspace-empty">No files found</div>
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

  .workspace-empty {
    padding: 0.5rem 0.25rem;
    color: var(--color-muted-foreground);
    font-size: 0.8rem;
  }
</style>
