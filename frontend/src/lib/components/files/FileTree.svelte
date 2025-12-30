<script lang="ts">
  import { onMount } from 'svelte';
  import { Folder } from 'lucide-svelte';
  import { treeStore } from '$lib/stores/tree';
  import FileTreeNode from './FileTreeNode.svelte';
  import SidebarLoading from '$lib/components/left-sidebar/SidebarLoading.svelte';
  import SidebarEmptyState from '$lib/components/left-sidebar/SidebarEmptyState.svelte';
  import type { FileNode } from '$lib/types/file';

  export let basePath: string = 'documents';
  export let emptyMessage: string = 'No files found';
  export let hideExtensions: boolean = false;
  export let onFileClick: ((path: string) => void) | undefined = undefined;

  // Reactive variables for tree data
  $: treeData = $treeStore.trees[basePath];
  $: children = treeData?.children || [];
  $: loading = treeData?.loading || false;

  onMount(() => {
    treeStore.load(basePath);
  });

  function handleToggle(path: string) {
    treeStore.toggleExpanded(basePath, path);
  }
</script>

<div class="file-tree">
  {#if loading}
    <SidebarLoading message="Loading files..." />
  {:else if children.length > 0}
    {#each children as child}
      <FileTreeNode node={child} level={0} onToggle={handleToggle} {basePath} {hideExtensions} {onFileClick} />
    {/each}
  {:else}
    <SidebarEmptyState icon={Folder} title={emptyMessage} />
  {/if}
</div>

<style>
  .file-tree {
    display: flex;
    flex-direction: column;
    overflow-y: auto;
    flex: 1;
    min-height: 0;
    padding-bottom: 80px;
  }

  /* Empty state handled by SidebarEmptyState */
</style>
