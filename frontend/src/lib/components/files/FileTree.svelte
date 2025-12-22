<script lang="ts">
  import { onMount } from 'svelte';
  import { filesStore } from '$lib/stores/files';
  import FileTreeNode from './FileTreeNode.svelte';
  import type { FileNode } from '$lib/types/file';

  export let basePath: string = 'documents';
  export let emptyMessage: string = 'No files found';
  export let hideExtensions: boolean = false;
  export let onFileClick: ((path: string) => void) | undefined = undefined;

  // Reactive variables for tree data
  $: treeData = $filesStore.trees[basePath];
  $: children = treeData?.children || [];
  $: loading = treeData?.loading || false;

  onMount(() => {
    filesStore.load(basePath);
  });

  function handleToggle(path: string) {
    filesStore.toggleExpanded(basePath, path);
  }
</script>

<div class="file-tree">
  {#if loading}
    <div class="loading">Loading files...</div>
  {:else if children.length > 0}
    {#each children as child}
      <FileTreeNode node={child} level={0} onToggle={handleToggle} {basePath} {hideExtensions} {onFileClick} />
    {/each}
  {:else}
    <div class="empty">{emptyMessage}</div>
  {/if}
</div>

<style>
  .file-tree {
    display: flex;
    flex-direction: column;
    overflow-y: auto;
    max-height: 400px;
    padding-bottom: 80px;
  }

  .loading,
  .empty {
    padding: 1rem;
    text-align: center;
    color: var(--color-muted-foreground);
    font-size: 0.875rem;
  }
</style>
