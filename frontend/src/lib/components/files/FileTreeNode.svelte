<script lang="ts">
  import { tick } from 'svelte';
  import {
    ChevronRight,
    ChevronDown,
    FileText,
    Folder,
    FolderOpen
  } from 'lucide-svelte';
  import { treeStore } from '$lib/stores/tree';
  import { editorStore } from '$lib/stores/editor';
  import DeleteDialogController from '$lib/components/files/DeleteDialogController.svelte';
  import FileTreeContextMenu from '$lib/components/files/FileTreeContextMenu.svelte';
  import { useFileActions } from '$lib/hooks/useFileActions';
  import type { FileNode } from '$lib/types/file';

  export let node: FileNode;
  export let level: number = 0;
  export let onToggle: (path: string) => void;
  export let basePath: string = 'documents';
  export let hideExtensions: boolean = false;
  export let onFileClick: ((path: string) => void) | undefined = undefined;
  export let showActions: boolean = true;
  export let forceExpand: boolean = false;

  let isEditing = false;
  let editedName = node.name;
  let deleteDialog: { openDialog: (name: string) => void } | null = null;
  let editInput: HTMLInputElement | null = null;
  let folderOptions: { label: string; value: string; depth: number }[] = [];

  $: isExpanded = forceExpand || node.expanded || false;
  $: hasChildren = node.children && node.children.length > 0;
  $: itemType = node.type === 'directory' ? 'folder' : 'file';

  // Display name: remove extension for files if hideExtensions is true
  $: displayName = (hideExtensions && node.type === 'file')
    ? node.name.replace(/\.[^/.]+$/, '')
    : node.name;

  const actions = useFileActions({
    getNode: () => node,
    getBasePath: () => basePath,
    getHideExtensions: () => hideExtensions,
    getEditedName: () => editedName,
    setEditedName: (value) => (editedName = value),
    setIsEditing: (value) => (isEditing = value),
    requestDelete: () => deleteDialog?.openDialog(node.name),
    setFolderOptions: (value) => (folderOptions = value),
    getDisplayName: () => displayName,
    editorStore,
    treeStore
  });

  function handleClick() {
    if (node.type === 'directory') {
      onToggle(node.path);
    } else if (node.type === 'file' && onFileClick) {
      onFileClick(node.path);
    }
  }

  const handleRenameKeydown = (event: KeyboardEvent) => {
    if (event.key === 'Escape') {
      actions.cancelRename();
    } else if (event.key === 'Enter') {
      actions.saveRename();
    }
  };

  $: if (isEditing) {
    tick().then(() => {
      editInput?.focus();
      editInput?.select();
    });
  }

</script>

<DeleteDialogController
  bind:this={deleteDialog}
  itemType={itemType}
  onConfirm={actions.confirmDelete}
/>

<div class="tree-node" style="padding-left: {level * 1}rem;">
  <div class="node-content">
    <button
      class="node-button"
      class:expandable={node.type === 'directory'}
      on:click={handleClick}
    >
      {#if node.type === 'directory'}
        <span class="chevron">
          {#if isExpanded}
            <ChevronDown size={16} />
          {:else}
            <ChevronRight size={16} />
          {/if}
        </span>
        <span class="icon">
          {#if isExpanded}
            <FolderOpen size={16} />
          {:else}
            <Folder size={16} />
          {/if}
        </span>
      {:else}
        <span class="icon file-icon">
          <FileText size={16} />
        </span>
      {/if}
      {#if isEditing}
        <input
          type="text"
          class="name-input"
          bind:this={editInput}
          bind:value={editedName}
          on:blur={actions.saveRename}
          on:keydown={handleRenameKeydown}
          on:click={(e) => e.stopPropagation()}
        />
      {:else}
        <span class="name">{displayName}</span>
      {/if}
    </button>

    {#if showActions}
      <div class="actions">
        <FileTreeContextMenu
          {node}
          {basePath}
          {folderOptions}
          onRename={actions.startRename}
          onDelete={actions.openDeleteDialog}
          onMoveOpen={actions.buildFolderOptions}
          onMoveFile={actions.handleMove}
          onMoveFolder={actions.handleMoveFolder}
          onPinToggle={actions.handlePinToggle}
          onArchive={actions.handleArchive}
          onUnarchive={actions.handleUnarchive}
          onDownload={actions.handleDownload}
        />
      </div>
    {/if}
  </div>
</div>

{#if isExpanded && hasChildren}
  {#each node.children as child}
    <svelte:self
      node={child}
      level={level + 1}
      {onToggle}
      {basePath}
      {hideExtensions}
      {onFileClick}
      {showActions}
      {forceExpand}
    />
  {/each}
{/if}

<style>
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

  .file-icon {
    margin-left: 1rem;
    color: var(--color-muted-foreground);
  }

  .name {
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .name-input {
    flex: 1;
    font-size: 0.875rem;
    padding: 0.25rem 0.5rem;
    background-color: var(--color-sidebar-accent);
    color: var(--color-sidebar-foreground);
    border: 1px solid var(--color-sidebar-border);
    border-radius: 0.25rem;
    outline: none;
  }

  .name-input:focus {
    border-color: var(--color-sidebar-primary);
  }

  .actions {
    position: relative;
    display: flex;
    align-items: center;
  }
</style>
