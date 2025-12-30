<script lang="ts">
  import { onDestroy } from 'svelte';
  import {
    MoreVertical,
    Trash2,
    Pencil,
    Pin,
    PinOff,
    FolderInput,
    Archive,
    Download
  } from 'lucide-svelte';
  import type { FileNode } from '$lib/types/file';

  export let node: FileNode;
  export let basePath: string;
  export let folderOptions: { label: string; value: string; depth: number }[] = [];

  export let onRename: () => void;
  export let onDelete: () => void;
  export let onMoveOpen: (excludePath?: string) => void;
  export let onMoveFile: (folder: string) => void;
  export let onMoveFolder: (folder: string) => void;
  export let onPinToggle: () => void;
  export let onArchive: () => void;
  export let onUnarchive: () => void;
  export let onDownload: () => void;

  let showMenu = false;
  let showMoveMenu = false;
  let menuElement: HTMLDivElement | null = null;
  let menuButton: HTMLButtonElement | null = null;
  let menuTimeout: ReturnType<typeof setTimeout> | null = null;
  let removeOutsideListener: (() => void) | null = null;

  const toggleMenu = (event: MouseEvent) => {
    event.stopPropagation();
    showMenu = !showMenu;
  };

  const closeMenu = () => {
    showMenu = false;
    showMoveMenu = false;
  };

  const handleRename = (event: MouseEvent) => {
    event.stopPropagation();
    onRename();
    closeMenu();
  };

  const handleMoveToggle = (event: MouseEvent) => {
    event.stopPropagation();
    showMoveMenu = !showMoveMenu;
    const exclude = node.type === 'directory' ? node.path.replace(/^folder:/, '') : undefined;
    onMoveOpen(exclude);
  };

  const handleMove = async (folder: string) => {
    if (node.type === 'directory') {
      await onMoveFolder(folder);
    } else {
      await onMoveFile(folder);
    }
    closeMenu();
  };

  const handlePinToggle = async (event: MouseEvent) => {
    event.stopPropagation();
    await onPinToggle();
    closeMenu();
  };

  const handleArchive = async (event: MouseEvent) => {
    event.stopPropagation();
    await onArchive();
    closeMenu();
  };

  const handleUnarchive = async (event: MouseEvent) => {
    event.stopPropagation();
    await onUnarchive();
    closeMenu();
  };

  const handleDownload = async (event: MouseEvent) => {
    event.stopPropagation();
    await onDownload();
    closeMenu();
  };

  const handleDelete = (event: MouseEvent) => {
    event.stopPropagation();
    onDelete();
    closeMenu();
  };

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

<button class="menu-btn" on:click={toggleMenu} aria-label="More options" bind:this={menuButton}>
  <MoreVertical size={16} />
</button>

{#if showMenu}
  <div class="menu" role="menu" tabindex="-1" bind:this={menuElement}>
    <button class="menu-item" on:click={handleRename}>
      <Pencil size={16} />
      <span>Rename</span>
    </button>
    {#if node.type === 'file'}
      {#if basePath === 'notes'}
        <button class="menu-item" on:click={handlePinToggle}>
          {#if node.pinned}
            <PinOff size={16} />
            <span>Unpin</span>
          {:else}
            <Pin size={16} />
            <span>Pin</span>
          {/if}
        </button>
        {#if node.archived}
          <button class="menu-item" on:click={handleUnarchive}>
            <Archive size={16} />
            <span>Unarchive</span>
          </button>
        {:else}
          <button class="menu-item" on:click={handleMoveToggle}>
            <FolderInput size={16} />
            <span>Move</span>
          </button>
          {#if showMoveMenu}
            <div class="menu-submenu">
              {#each folderOptions as option (option.value)}
                <button
                  class="menu-subitem"
                  style={`padding-left: ${option.depth * 12 + 12}px`}
                  on:click={() => handleMove(option.value)}
                >
                  {option.label}
                </button>
              {/each}
            </div>
          {/if}
          <button class="menu-item" on:click={handleArchive}>
            <Archive size={16} />
            <span>Archive</span>
          </button>
        {/if}
      {:else}
        <button class="menu-item" on:click={handleMoveToggle}>
          <FolderInput size={16} />
          <span>Move</span>
        </button>
        {#if showMoveMenu}
          <div class="menu-submenu">
            {#each folderOptions as option (option.value)}
              <button
                class="menu-subitem"
                style={`padding-left: ${option.depth * 12 + 12}px`}
                on:click={() => handleMove(option.value)}
              >
                {option.label}
              </button>
            {/each}
          </div>
        {/if}
      {/if}
      <button class="menu-item" on:click={handleDownload}>
        <Download size={16} />
        <span>Download</span>
      </button>
    {:else if node.type === 'directory'}
      <button class="menu-item" on:click={handleMoveToggle}>
        <FolderInput size={16} />
        <span>Move</span>
      </button>
      {#if showMoveMenu}
        <div class="menu-submenu">
          {#each folderOptions as option (option.value)}
            <button
              class="menu-subitem"
              style={`padding-left: ${option.depth * 12 + 12}px`}
              on:click={() => handleMove(option.value)}
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

<style>
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

  :global(.node-content:hover) .menu-btn {
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
