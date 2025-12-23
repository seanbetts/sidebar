<script lang="ts">
  import { onDestroy, tick } from 'svelte';
  import {
    ChevronRight,
    ChevronDown,
    File,
    Folder,
    FolderOpen,
    MoreVertical,
    Trash2,
    Pencil,
    Pin,
    PinOff,
    FolderInput,
    Archive,
    Download
  } from 'lucide-svelte';
  import { get } from 'svelte/store';
  import { filesStore } from '$lib/stores/files';
  import { editorStore } from '$lib/stores/editor';
  import NoteDeleteDialog from '$lib/components/files/NoteDeleteDialog.svelte';
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
  let isDeleteDialogOpen = false;
  let editInput: HTMLInputElement | null = null;
  let menuElement: HTMLDivElement | null = null;
  let menuButton: HTMLButtonElement | null = null;
  let menuTimeout: ReturnType<typeof setTimeout> | null = null;
  let removeOutsideListener: (() => void) | null = null;
  let showMoveMenu = false;
  let folderOptions: { label: string; value: string; depth: number }[] = [];

  $: isExpanded = node.expanded || false;
  $: hasChildren = node.children && node.children.length > 0;
  $: itemType = node.type === 'directory' ? 'folder' : 'file';

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

  function closeMenu() {
    showMenu = false;
    showMoveMenu = false;
  }

  function handleRename(event: MouseEvent) {
    event.stopPropagation();
    // Strip extension for files when hideExtensions is true
    if (hideExtensions && node.type === 'file') {
      editedName = node.name.replace(/\.[^/.]+$/, '');
    } else {
      editedName = node.name;
    }
    isEditing = true;
    showMenu = false;
  }

  async function saveRename() {
    if (editedName.trim() && editedName !== node.name) {
      try {
        // Add extension back if missing for files with hideExtensions
        let newName = editedName.trim();
        if (hideExtensions && node.type === 'file') {
          const extension = node.name.match(/\.[^/.]+$/)?.[0] || '';
          if (!newName.endsWith(extension)) {
            newName += extension;
          }
        }

        const response = basePath === 'notes'
          ? await fetch(
              node.type === 'directory'
                ? '/api/notes/folders/rename'
                : `/api/notes/${node.path}/rename`,
              {
                method: 'PATCH',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(
                  node.type === 'directory'
                    ? { oldPath: node.path.replace(/^folder:/, ''), newName }
                    : { newName }
                )
              }
            )
          : await fetch(`/api/files/rename`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                basePath,
                oldPath: node.path,
                newName
              })
            });

        if (!response.ok) throw new Error('Failed to rename');

        // Update editor store if the currently open note was renamed
        const currentStore = get(editorStore);
        if (currentStore.currentNoteId === node.path) {
          editorStore.updateNoteName(newName);
        }

        // Reload the tree
        await filesStore.load(basePath);
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
    isDeleteDialogOpen = true;
    showMenu = false;
  }

  function buildFolderOptions(excludePath?: string) {
    const state = get(filesStore);
    const tree = state.trees[basePath];
    const rootChildren = tree?.children || [];
    const options: { label: string; value: string; depth: number }[] = [
      { label: 'Notes', value: '', depth: 0 }
    ];

    const walk = (nodes: FileNode[], depth: number) => {
      for (const child of nodes) {
        if (child.type !== 'directory') continue;
        const folderName = child.name;
        if (folderName === 'Archive') continue;
        const folderPath = child.path.replace(/^folder:/, '');
        if (excludePath && (folderPath === excludePath || folderPath.startsWith(`${excludePath}/`))) {
          if (child.children?.length) {
            walk(child.children, depth + 1);
          }
          continue;
        }
        options.push({ label: folderName, value: folderPath, depth });
        if (child.children?.length) {
          walk(child.children, depth + 1);
        }
      }
    };

    walk(rootChildren, 1);
    folderOptions = options;
  }

  async function handlePinToggle(event: MouseEvent) {
    event.stopPropagation();
    if (node.type !== 'file') return;
    try {
      const pinned = !node.pinned;
      const response = await fetch(`/api/notes/${node.path}/pin`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pinned })
      });
      if (!response.ok) throw new Error('Failed to update pin');
      await filesStore.load(basePath);
    } catch (error) {
      console.error('Failed to pin note:', error);
    } finally {
      closeMenu();
    }
  }

  async function handleArchive(event: MouseEvent) {
    event.stopPropagation();
    if (node.type !== 'file') return;
    try {
      const response = await fetch(`/api/notes/${node.path}/archive`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ archived: true })
      });
      if (!response.ok) throw new Error('Failed to archive note');
      await filesStore.load(basePath);
    } catch (error) {
      console.error('Failed to archive note:', error);
    } finally {
      closeMenu();
    }
  }

  async function handleMove(event: MouseEvent, folder: string) {
    event.stopPropagation();
    if (node.type !== 'file') return;
    try {
      const response = await fetch(`/api/notes/${node.path}/move`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ folder })
      });
      if (!response.ok) throw new Error('Failed to move note');
      await filesStore.load(basePath);
    } catch (error) {
      console.error('Failed to move note:', error);
    } finally {
      closeMenu();
    }
  }

  async function handleMoveFolder(event: MouseEvent, newParent: string) {
    event.stopPropagation();
    if (node.type !== 'directory') return;
    try {
      const response = await fetch('/api/notes/folders/move', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          oldPath: node.path.replace(/^folder:/, ''),
          newParent
        })
      });
      if (!response.ok) throw new Error('Failed to move folder');
      await filesStore.load(basePath);
    } catch (error) {
      console.error('Failed to move folder:', error);
    } finally {
      closeMenu();
    }
  }

  async function handleDownload(event: MouseEvent) {
    event.stopPropagation();
    if (node.type !== 'file') return;
    try {
      if (basePath === 'notes') {
        const link = document.createElement('a');
        link.href = `/api/notes/${node.path}/download`;
        link.download = `${displayName}.md`;
        document.body.appendChild(link);
        link.click();
        link.remove();
        return;
      }

      const response = await fetch(
        `/api/files/content?basePath=${basePath}&path=${encodeURIComponent(node.path)}`
      );
      if (!response.ok) throw new Error('Failed to load note content');
      const data = await response.json();
      const blob = new Blob([data.content || ''], { type: 'text/markdown' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = data.name || `${displayName}.md`;
      document.body.appendChild(link);
      link.click();
      link.remove();
      URL.revokeObjectURL(url);
    } catch (error) {
      console.error('Failed to download note:', error);
    } finally {
      closeMenu();
    }
  }

  async function confirmDelete() {
    try {
      const response = basePath === 'notes'
        ? await fetch(
            node.type === 'directory'
              ? '/api/notes/folders'
              : `/api/notes/${node.path}`,
            {
              method: 'DELETE',
              headers: { 'Content-Type': 'application/json' },
              body: node.type === 'directory'
                ? JSON.stringify({ path: node.path.replace(/^folder:/, '') })
                : undefined
            }
          )
        : await fetch(`/api/files/delete`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              basePath,
              path: node.path
            })
          });

      if (!response.ok) throw new Error('Failed to delete');

      // Close editor if the deleted file was currently open
      const currentStore = get(editorStore);
      if (currentStore.currentNoteId === node.path) {
        editorStore.reset();
      }

      // Reload the tree
      await filesStore.load(basePath);
      isDeleteDialogOpen = false;
    } catch (error) {
      console.error('Failed to delete:', error);
    }
  }

  $: if (isEditing) {
    tick().then(() => {
      editInput?.focus();
      editInput?.select();
    });
  }

  $: if (showMenu) {
    if (menuTimeout) clearTimeout(menuTimeout);
    menuTimeout = setTimeout(() => {
      closeMenu();
    }, 4000);

    if (!removeOutsideListener) {
      const handleOutsideClick = (event: MouseEvent) => {
        const target = event.target as Node;
        if (menuElement?.contains(target) || menuButton?.contains(target)) {
          return;
        }
        closeMenu();
      };
      document.addEventListener('click', handleOutsideClick, true);
      removeOutsideListener = () => document.removeEventListener('click', handleOutsideClick, true);
    }
  } else {
    if (menuTimeout) {
      clearTimeout(menuTimeout);
      menuTimeout = null;
    }
    if (removeOutsideListener) {
      removeOutsideListener();
      removeOutsideListener = null;
    }
  }

  onDestroy(() => {
    if (menuTimeout) clearTimeout(menuTimeout);
    if (removeOutsideListener) removeOutsideListener();
  });
</script>

<NoteDeleteDialog
  bind:open={isDeleteDialogOpen}
  itemType={itemType}
  itemName={node.name}
  onConfirm={confirmDelete}
  onCancel={() => (isDeleteDialogOpen = false)}
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
          <File size={16} />
        </span>
      {/if}
      {#if isEditing}
        <input
          type="text"
          class="name-input"
          bind:this={editInput}
          bind:value={editedName}
          on:blur={saveRename}
          on:keydown={cancelRename}
          on:click={(e) => e.stopPropagation()}
        />
      {:else}
        <span class="name">{displayName}</span>
      {/if}
    </button>

    <div class="actions">
      <button class="menu-btn" on:click={toggleMenu} aria-label="More options" bind:this={menuButton}>
        <MoreVertical size={16} />
      </button>

      {#if showMenu}
        <div class="menu" bind:this={menuElement} on:click|stopPropagation>
          <button class="menu-item" on:click={handleRename}>
            <Pencil size={16} />
            <span>Rename</span>
          </button>
          {#if node.type === 'file'}
            <button class="menu-item" on:click={handlePinToggle}>
              {#if node.pinned}
                <PinOff size={16} />
                <span>Unpin</span>
              {:else}
                <Pin size={16} />
                <span>Pin</span>
              {/if}
            </button>
            <button
              class="menu-item"
              on:click={(event) => {
                event.stopPropagation();
                showMoveMenu = !showMoveMenu;
                buildFolderOptions();
              }}
            >
              <FolderInput size={16} />
              <span>Move</span>
            </button>
            {#if showMoveMenu}
              <div class="menu-submenu">
                {#each folderOptions as option (option.value)}
                  <button
                    class="menu-subitem"
                    style={`padding-left: ${option.depth * 12 + 12}px`}
                    on:click={(event) => handleMove(event, option.value)}
                  >
                    {option.label}
                  </button>
                {/each}
              </div>
            {/if}
            {#if !node.archived}
              <button class="menu-item" on:click={handleArchive}>
                <Archive size={16} />
                <span>Archive</span>
              </button>
            {/if}
            <button class="menu-item" on:click={handleDownload}>
              <Download size={16} />
              <span>Download</span>
            </button>
          {:else if node.type === 'directory'}
            <button
              class="menu-item"
              on:click={(event) => {
                event.stopPropagation();
                showMoveMenu = !showMoveMenu;
                buildFolderOptions(node.path.replace(/^folder:/, ''));
              }}
            >
              <FolderInput size={16} />
              <span>Move</span>
            </button>
            {#if showMoveMenu}
              <div class="menu-submenu">
                {#each folderOptions as option (option.value)}
                  <button
                    class="menu-subitem"
                    style={`padding-left: ${option.depth * 12 + 12}px`}
                    on:click={(event) => handleMoveFolder(event, option.value)}
                  >
                    {option.label}
                  </button>
                {/each}
              </div>
            {/if}
          {/if}
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

  .menu-submenu {
    padding: 0.25rem 0;
    border-top: 1px solid var(--color-border);
  }

  .menu-subitem {
    display: block;
    width: 100%;
    padding: 0.35rem 0.75rem;
    background: none;
    border: none;
    cursor: pointer;
    font-size: 0.8rem;
    text-align: left;
    color: var(--color-popover-foreground);
  }

  .menu-subitem:hover {
    background-color: var(--color-accent);
  }
</style>
