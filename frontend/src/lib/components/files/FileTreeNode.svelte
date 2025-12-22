<script lang="ts">
  import { ChevronRight, ChevronDown, File, Folder, FolderOpen, MoreVertical, Trash2, Pencil } from 'lucide-svelte';
  import type { FileNode } from '$lib/types/file';

  export let node: FileNode;
  export let level: number = 0;
  export let onToggle: (path: string) => void;
  export let basePath: string = 'documents';
  export let hideExtensions: boolean = false;
  export let onFileClick: ((path: string) => void) | undefined = undefined;

  let showMenu = false;
  let isEditing = false;
  let editedName = node.name;

  $: isExpanded = node.expanded || false;
  $: hasChildren = node.children && node.children.length > 0;

  // Display name: remove extension for files if hideExtensions is true
  $: displayName = (hideExtensions && node.type === 'file')
    ? node.name.replace(/\.[^/.]+$/, '')
    : node.name;

  function handleClick() {
    if (node.type === 'directory') {
      onToggle(node.path);
    } else if (node.type === 'file' && onFileClick) {
      onFileClick(node.path);
    }
  }

  function toggleMenu(event: MouseEvent) {
    event.stopPropagation();
    showMenu = !showMenu;
  }

  function handleRename(event: MouseEvent) {
    event.stopPropagation();
    editedName = node.name;
    isEditing = true;
    showMenu = false;
  }

  async function saveRename() {
    if (editedName.trim() && editedName !== node.name) {
      try {
        const response = await fetch(`/api/files/rename`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            basePath,
            oldPath: node.path,
            newName: editedName.trim()
          })
        });

        if (!response.ok) throw new Error('Failed to rename');

        // Reload the tree
        window.location.reload();
      } catch (error) {
        console.error('Failed to rename:', error);
        editedName = node.name;
      }
    }
    isEditing = false;
  }

  function cancelRename(event: KeyboardEvent) {
    if (event.key === 'Escape') {
      editedName = node.name;
      isEditing = false;
    } else if (event.key === 'Enter') {
      saveRename();
    }
  }

  async function handleDelete(event: MouseEvent) {
    event.stopPropagation();
    const itemType = node.type === 'directory' ? 'folder' : 'file';
    if (confirm(`Delete ${itemType} "${node.name}"?`)) {
      try {
        const response = await fetch(`/api/files/delete`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            basePath,
            path: node.path
          })
        });

        if (!response.ok) throw new Error('Failed to delete');

        // Reload the tree
        window.location.reload();
      } catch (error) {
        console.error('Failed to delete:', error);
      }
    }
    showMenu = false;
  }
</script>

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
          <File size={16} />
        </span>
      {/if}
      {#if isEditing}
        <input
          type="text"
          class="name-input"
          bind:value={editedName}
          on:blur={saveRename}
          on:keydown={cancelRename}
          on:click={(e) => e.stopPropagation()}
          autofocus
        />
      {:else}
        <span class="name">{displayName}</span>
      {/if}
    </button>

    <div class="actions">
      <button class="menu-btn" on:click={toggleMenu} aria-label="More options">
        <MoreVertical size={16} />
      </button>

      {#if showMenu}
        <div class="menu">
          <button class="menu-item" on:click={handleRename}>
            <Pencil size={16} />
            <span>Rename</span>
          </button>
          <button class="menu-item delete" on:click={handleDelete}>
            <Trash2 size={16} />
            <span>Delete</span>
          </button>
        </div>
      {/if}
    </div>
  </div>
</div>

{#if isExpanded && hasChildren}
  {#each node.children as child}
    <svelte:self node={child} level={level + 1} {onToggle} {basePath} {hideExtensions} {onFileClick} />
  {/each}
{/if}

<style>
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
    align-items: flex-start;
  }

  .menu-btn {
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
    transition: all 0.2s;
  }

  .node-content:hover .menu-btn {
    opacity: 1;
  }

  .menu-btn:hover {
    background-color: var(--color-accent);
  }

  .menu {
    position: absolute;
    top: 100%;
    right: 0;
    margin-top: 0.25rem;
    background-color: var(--color-popover);
    border: 1px solid var(--color-border);
    border-radius: 0.375rem;
    box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
    z-index: 9999;
    min-width: 120px;
  }

  .menu-item {
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

  .menu-item:hover {
    background-color: var(--color-accent);
  }

  .menu-item.delete {
    color: var(--color-destructive);
  }
</style>
