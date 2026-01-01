<script lang="ts">
  import { FileTerminal, MoreHorizontal, Pin, PinOff, Pencil, Download, Archive, ArchiveRestore, Trash2 } from 'lucide-svelte';
  import type { WebsiteItem } from '$lib/stores/websites';

  export let site: WebsiteItem;
  export let isMenuOpen = false;
  export let archived = false;
  export let onOpen: (site: WebsiteItem) => void;
  export let onOpenMenu: (event: MouseEvent, site: WebsiteItem) => void;
  export let onPin: (site: WebsiteItem) => void;
  export let onRename: (site: WebsiteItem) => void;
  export let onDownload: (site: WebsiteItem) => void;
  export let onArchive: (site: WebsiteItem) => void;
  export let onDelete: (site: WebsiteItem) => void;
  export let formatDomain: (domain: string) => string;
</script>

<div class="website-item">
  <button class="website-main" on:click={() => onOpen(site)}>
    <span class="website-icon">
      <FileTerminal />
    </span>
    <div class="website-text">
      <span class="website-title">{site.title}</span>
      <span class="website-domain">{formatDomain(site.domain)}</span>
    </div>
  </button>
  <button class="website-menu-btn" on:click={(event) => onOpenMenu(event, site)} aria-label="More options">
    <MoreHorizontal size={16} />
  </button>
  {#if isMenuOpen}
    <div class="website-menu">
      <button class="menu-item" on:click={() => onPin(site)}>
        {#if site.pinned}
          <PinOff size={16} />
          <span>Unpin</span>
        {:else}
          <Pin size={16} />
          <span>Pin</span>
        {/if}
      </button>
      <button class="menu-item" on:click={() => onRename(site)}>
        <Pencil size={16} />
        <span>Rename</span>
      </button>
      <button class="menu-item" on:click={() => onDownload(site)}>
        <Download size={16} />
        <span>Download</span>
      </button>
      <button class="menu-item" on:click={() => onArchive(site)}>
        {#if archived}
          <ArchiveRestore size={16} />
        {:else}
          <Archive size={16} />
        {/if}
        <span>{archived ? 'Unarchive' : 'Archive'}</span>
      </button>
      <button class="menu-item" on:click={() => onDelete(site)}>
        <Trash2 size={16} />
        <span>Delete</span>
      </button>
    </div>
  {/if}
</div>

<style>
  .website-item {
    position: relative;
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.4rem 0.5rem;
    border-radius: 0.5rem;
    color: var(--color-sidebar-foreground);
    background: transparent;
    border: none;
    width: 100%;
    text-align: left;
    transition: background-color 0.2s ease;
  }

  .website-item:hover {
    background-color: var(--color-sidebar-accent);
  }

  .website-main {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    background: none;
    border: none;
    cursor: pointer;
    flex: 1;
    min-width: 0;
    text-align: left;
    padding: 0;
    color: inherit;
  }

  .website-menu-btn {
    display: inline-flex;
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

  .website-item:hover .website-menu-btn {
    opacity: 1;
  }

  .website-menu-btn:hover {
    background-color: var(--color-accent);
  }

  .website-menu {
    position: absolute;
    top: 100%;
    right: 0.25rem;
    margin-top: 0.25rem;
    background-color: var(--color-popover);
    border: 1px solid var(--color-border);
    border-radius: 0.375rem;
    box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
    z-index: 9999;
    min-width: 150px;
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

  .website-icon {
    flex-shrink: 0;
    width: 16px;
    height: 16px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
  }

  .website-icon :global(svg) {
    width: 16px;
    height: 16px;
  }

  .website-text {
    display: flex;
    flex-direction: column;
    min-width: 0;
    overflow: hidden;
  }

  .website-title {
    font-size: 0.85rem;
    font-weight: 500;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 100%;
  }

  .website-domain {
    font-size: 0.7rem;
    color: var(--color-muted-foreground);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
