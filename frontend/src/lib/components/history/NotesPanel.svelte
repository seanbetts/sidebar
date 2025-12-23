<script lang="ts">
  import { onMount } from 'svelte';
  import { ChevronRight } from 'lucide-svelte';
  import { filesStore } from '$lib/stores/files';
  import FileTreeNode from '$lib/components/files/FileTreeNode.svelte';
  import * as Collapsible from '$lib/components/ui/collapsible/index.js';
  import type { FileNode } from '$lib/types/file';

  export let basePath: string = 'notes';
  export let emptyMessage: string = 'No notes found';
  export let hideExtensions: boolean = false;
  export let onFileClick: ((path: string) => void) | undefined = undefined;

  $: treeData = $filesStore.trees[basePath];
  $: children = treeData?.children || [];
  $: loading = treeData?.loading || false;

  const ARCHIVE_FOLDER = 'Archive';

  onMount(() => {
    filesStore.load(basePath);
  });

  function handleToggle(path: string) {
    filesStore.toggleExpanded(basePath, path);
  }

  function collectPinned(
    nodes: FileNode[],
    archived: boolean = false,
    acc: FileNode[] = []
  ): FileNode[] {
    for (const node of nodes) {
      const isArchive = archived || (node.type === 'directory' && node.name === ARCHIVE_FOLDER);
      if (node.type === 'file' && node.pinned && !isArchive) {
        acc.push(node);
      }
      if (node.children && node.children.length > 0) {
        collectPinned(node.children, isArchive, acc);
      }
    }
    return acc;
  }

  function filterNodes(
    nodes: FileNode[],
    options: { excludePinned: boolean; excludeArchive: boolean },
    archived: boolean = false
  ): FileNode[] {
    const results: FileNode[] = [];

    for (const node of nodes) {
      const isArchive = archived || (node.type === 'directory' && node.name === ARCHIVE_FOLDER);
      if (options.excludeArchive && isArchive) {
        continue;
      }
      if (options.excludePinned && node.type === 'file' && node.pinned) {
        continue;
      }

      if (node.type === 'directory') {
        const filteredChildren = filterNodes(
          node.children || [],
          options,
          isArchive
        );
        if (filteredChildren.length === 0) {
          continue;
        }
        results.push({ ...node, children: filteredChildren });
      } else {
        results.push(node);
      }
    }

    return results;
  }

  function getArchiveChildren(nodes: FileNode[]): FileNode[] {
    const archiveNode = nodes.find(
      (node) => node.type === 'directory' && node.name === ARCHIVE_FOLDER
    );
    return archiveNode?.children || [];
  }

  $: pinnedNodes = collectPinned(children);
  $: mainNodes = filterNodes(children, { excludePinned: true, excludeArchive: true });
  $: archiveNodes = getArchiveChildren(children);
</script>

{#if loading}
  <div class="notes-empty">Loading notes...</div>
{:else}
  <div class="notes-sections">
    <div class="notes-block">
      <div class="notes-block-title">Pinned</div>
      {#if pinnedNodes.length > 0}
        <div class="notes-block-content">
          {#each pinnedNodes as node (node.path)}
            <FileTreeNode
              node={node}
              level={0}
              onToggle={handleToggle}
              {basePath}
              {hideExtensions}
              {onFileClick}
            />
          {/each}
        </div>
      {:else}
        <div class="notes-empty">No pinned notes</div>
      {/if}
    </div>

    <div class="notes-block">
      <div class="notes-block-title">Notes</div>
      {#if mainNodes.length > 0}
        <div class="notes-block-content">
          {#each mainNodes as node (node.path)}
            <FileTreeNode
              node={node}
              level={0}
              onToggle={handleToggle}
              {basePath}
              {hideExtensions}
              {onFileClick}
            />
          {/each}
        </div>
      {:else}
        <div class="notes-empty">{emptyMessage}</div>
      {/if}
    </div>

    <div class="notes-block notes-archive">
      <Collapsible.Root defaultOpen={false} class="group/collapsible" data-collapsible-root>
        <div data-slot="sidebar-group" data-sidebar="group" class="relative flex w-full min-w-0 flex-col p-2">
          <Collapsible.Trigger
            data-slot="sidebar-group-label"
            data-sidebar="group-label"
            class="archive-trigger"
          >
            <span class="notes-block-title archive-label">Archive</span>
            <ChevronRight class="archive-chevron transition-transform group-data-[state=open]/collapsible:rotate-90" />
          </Collapsible.Trigger>
          <Collapsible.Content data-slot="collapsible-content" class="pt-1">
            <div data-slot="sidebar-group-content" data-sidebar="group-content" class="w-full text-sm">
              {#if archiveNodes.length > 0}
                <div class="notes-block-content">
                  {#each archiveNodes as node (node.path)}
                    <FileTreeNode
                      node={node}
                      level={0}
                      onToggle={handleToggle}
                      {basePath}
                      {hideExtensions}
                      {onFileClick}
                    />
                  {/each}
                </div>
              {:else}
                <div class="notes-empty">No archived notes</div>
              {/if}
            </div>
          </Collapsible.Content>
        </div>
      </Collapsible.Root>
    </div>
  </div>
{/if}

<style>
  .notes-sections {
    display: flex;
    flex-direction: column;
    gap: 1rem;
    flex: 1;
    min-height: 0;
    padding-top: 0.5rem;
  }

  .notes-block {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .notes-archive {
    margin-top: auto;
  }

  .notes-block-title {
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--color-muted-foreground);
    font-weight: 600;
    padding: 0 0.25rem;
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

  .archive-label {
    color: var(--color-muted-foreground);
  }

  :global(.archive-trigger:hover) .archive-label {
    color: var(--color-foreground);
  }

  .archive-chevron {
    width: 16px;
    height: 16px;
    flex-shrink: 0;
    color: var(--color-muted-foreground);
  }

  :global(.archive-trigger:hover) .archive-chevron {
    color: var(--color-foreground);
  }

  .notes-block-content {
    display: flex;
    flex-direction: column;
    gap: 0.15rem;
  }


  .notes-empty {
    padding: 0.5rem 0.25rem;
    color: var(--color-muted-foreground);
    font-size: 0.8rem;
  }
</style>
