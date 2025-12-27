<script lang="ts">
  import { onDestroy, tick } from 'svelte';
  import { ChevronRight, Globe, MoreVertical, Pin, PinOff, Pencil, Download, Archive, Trash2, Search } from 'lucide-svelte';
  import * as Collapsible from '$lib/components/ui/collapsible/index.js';
  import SidebarLoading from '$lib/components/left-sidebar/SidebarLoading.svelte';
  import SidebarEmptyState from '$lib/components/left-sidebar/SidebarEmptyState.svelte';
  import { websitesStore } from '$lib/stores/websites';
  import type { WebsiteItem } from '$lib/stores/websites';
  import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';
  import NoteDeleteDialog from '$lib/components/files/NoteDeleteDialog.svelte';

  const ARCHIVED_FLAG = 'archived';

  // Data loading is now handled by parent Sidebar component
  // onMount removed to prevent duplicate loads and initial flicker

  function isArchived(site: WebsiteItem) {
    return Boolean((site as WebsiteItem & Record<string, unknown>)[ARCHIVED_FLAG]);
  }

  function formatDomain(domain: string) {
    return domain.replace(/^www\./i, '');
  }

  $: searchQuery = $websitesStore.searchQuery;
  $: pinnedItems = $websitesStore.items.filter((site) => site.pinned && !isArchived(site));
  $: mainItems = $websitesStore.items.filter((site) => !site.pinned && !isArchived(site));
  $: archivedItems = $websitesStore.items.filter((site) => isArchived(site));
  $: totalItems = $websitesStore.items.length;

  let activeMenuId: string | null = null;
  let menuTimeout: ReturnType<typeof setTimeout> | null = null;
  let removeOutsideListener: (() => void) | null = null;
  let isRenameDialogOpen = false;
  let renameValue = '';
  let renameInput: HTMLInputElement | null = null;
  let isDeleteDialogOpen = false;
  let selectedSite: WebsiteItem | null = null;

  function closeMenu() {
    activeMenuId = null;
  }

  function openMenu(event: MouseEvent, site: WebsiteItem) {
    event.stopPropagation();
    activeMenuId = site.id;
    selectedSite = site;
  }

  function scheduleMenuClose() {
    if (menuTimeout) clearTimeout(menuTimeout);
    menuTimeout = setTimeout(() => {
      closeMenu();
    }, 4000);
  }

  function ensureOutsideListener() {
    if (removeOutsideListener) return;
    const handler = (event: MouseEvent) => {
      const target = event.target as HTMLElement;
      if (target.closest('.website-menu') || target.closest('.website-menu-btn')) {
        return;
      }
      closeMenu();
    };
    document.addEventListener('click', handler, true);
    removeOutsideListener = () => document.removeEventListener('click', handler, true);
  }

  $: if (activeMenuId) {
    scheduleMenuClose();
    ensureOutsideListener();
  } else {
    if (menuTimeout) {
      clearTimeout(menuTimeout);
      menuTimeout = null;
    }
  }

  onDestroy(() => {
    if (menuTimeout) clearTimeout(menuTimeout);
    if (removeOutsideListener) removeOutsideListener();
  });

  function openRenameDialog(site: WebsiteItem) {
    selectedSite = site;
    renameValue = site.title || '';
    isRenameDialogOpen = true;
    closeMenu();
  }

  async function handleRename() {
    if (!selectedSite) return;
    const trimmed = renameValue.trim();
    if (!trimmed || trimmed === selectedSite.title) {
      isRenameDialogOpen = false;
      return;
    }
    const response = await fetch(`/api/websites/${selectedSite.id}/rename`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: trimmed })
    });
    if (!response.ok) {
      console.error('Failed to rename website');
      return;
    }
    await websitesStore.load(true);
    isRenameDialogOpen = false;
  }

  async function handlePin(site: WebsiteItem) {
    const response = await fetch(`/api/websites/${site.id}/pin`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pinned: !site.pinned })
    });
    if (!response.ok) {
      console.error('Failed to update pin');
      return;
    }
    await websitesStore.load(true);
    closeMenu();
  }

  async function handleArchive(site: WebsiteItem) {
    const response = await fetch(`/api/websites/${site.id}/archive`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ archived: !isArchived(site) })
    });
    if (!response.ok) {
      console.error('Failed to archive website');
      return;
    }
    await websitesStore.load(true);
    closeMenu();
  }

  function handleDownload(site: WebsiteItem) {
    const link = document.createElement('a');
    link.href = `/api/websites/${site.id}/download`;
    link.download = `${site.title || 'website'}.md`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    closeMenu();
  }

  function openDeleteDialog(site: WebsiteItem) {
    selectedSite = site;
    isDeleteDialogOpen = true;
    closeMenu();
  }

  async function handleDelete() {
    if (!selectedSite) return;
    const response = await fetch(`/api/websites/${selectedSite.id}`, {
      method: 'DELETE'
    });
    if (!response.ok) {
      console.error('Failed to delete website');
      return;
    }
    await websitesStore.load(true);
    isDeleteDialogOpen = false;
    selectedSite = null;
  }

  $: if (isRenameDialogOpen) {
    tick().then(() => {
      renameInput?.focus();
      renameInput?.select();
    });
  }
</script>

<AlertDialog.Root bind:open={isRenameDialogOpen}>
  <AlertDialog.Content
    onOpenAutoFocus={(event) => {
      event.preventDefault();
      renameInput?.focus();
      renameInput?.select();
    }}
  >
    <AlertDialog.Header>
      <AlertDialog.Title>Rename website</AlertDialog.Title>
      <AlertDialog.Description>Update the website title.</AlertDialog.Description>
    </AlertDialog.Header>
    <div class="py-2">
      <input
        class="w-full rounded-md border bg-background px-3 py-2 text-sm shadow-sm outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
        type="text"
        placeholder="Website title"
        bind:this={renameInput}
        bind:value={renameValue}
        on:keydown={(event) => {
          if (event.key === 'Enter') handleRename();
        }}
      />
    </div>
    <AlertDialog.Footer>
      <AlertDialog.Cancel onclick={() => (isRenameDialogOpen = false)}>Cancel</AlertDialog.Cancel>
      <AlertDialog.Action disabled={!renameValue.trim()} onclick={handleRename}>
        Rename
      </AlertDialog.Action>
    </AlertDialog.Footer>
  </AlertDialog.Content>
</AlertDialog.Root>

<NoteDeleteDialog
  bind:open={isDeleteDialogOpen}
  itemType="website"
  itemName={selectedSite?.title ?? ''}
  onConfirm={handleDelete}
  onCancel={() => (isDeleteDialogOpen = false)}
/>

<div class="websites-sections">
  {#if $websitesStore.error}
    <SidebarEmptyState
      icon={Globe}
      title="Unable to load websites"
      subtitle={$websitesStore.error}
    />
  {:else if $websitesStore.loading}
    <SidebarLoading message="Loading websites..." />
  {:else if !searchQuery && totalItems === 0}
    <SidebarEmptyState
      icon={Globe}
      title="No websites yet"
      subtitle="Save a link to start building your library."
    />
  {:else if searchQuery}
    <div class="websites-block">
      <div class="websites-block-title">Results</div>
      {#if $websitesStore.items.length === 0}
        <SidebarEmptyState
          icon={Search}
          title="No results"
          subtitle="Try a different search."
        />
      {:else}
        <div class="websites-list">
          {#each $websitesStore.items as site (site.id)}
            <div class="website-item">
              <button class="website-main" on:click={() => websitesStore.loadById(site.id)}>
              <span class="website-icon">
                <Globe />
              </span>
              <div class="website-text">
                <span class="website-title">{site.title}</span>
                <span class="website-domain">{formatDomain(site.domain)}</span>
              </div>
              </button>
              <button class="website-menu-btn" on:click={(event) => openMenu(event, site)} aria-label="More options">
                <MoreVertical size={14} />
              </button>
              {#if activeMenuId === site.id}
                <div class="website-menu">
                  <button class="menu-item" on:click={() => handlePin(site)}>
                    {#if site.pinned}
                      <PinOff size={14} />
                      <span>Unpin</span>
                    {:else}
                      <Pin size={14} />
                      <span>Pin</span>
                    {/if}
                  </button>
                  <button class="menu-item" on:click={() => openRenameDialog(site)}>
                    <Pencil size={14} />
                    <span>Rename</span>
                  </button>
                  <button class="menu-item" on:click={() => handleDownload(site)}>
                    <Download size={14} />
                    <span>Download</span>
                  </button>
                  <button class="menu-item" on:click={() => handleArchive(site)}>
                    <Archive size={14} />
                    <span>{isArchived(site) ? 'Unarchive' : 'Archive'}</span>
                  </button>
                  <button class="menu-item delete" on:click={() => openDeleteDialog(site)}>
                    <Trash2 size={14} />
                    <span>Delete</span>
                  </button>
                </div>
              {/if}
            </div>
          {/each}
        </div>
      {/if}
    </div>
  {:else}
    <div class="websites-block">
      <div class="websites-block-title">Pinned</div>
      {#if pinnedItems.length === 0}
        <div class="websites-empty">No pinned websites</div>
      {:else}
        <div class="websites-list">
          {#each pinnedItems as site (site.id)}
            <div class="website-item">
              <button class="website-main" on:click={() => websitesStore.loadById(site.id)}>
              <span class="website-icon">
                <Globe />
              </span>
              <div class="website-text">
                <span class="website-title">{site.title}</span>
                <span class="website-domain">{formatDomain(site.domain)}</span>
              </div>
              </button>
              <button class="website-menu-btn" on:click={(event) => openMenu(event, site)} aria-label="More options">
                <MoreVertical size={14} />
              </button>
              {#if activeMenuId === site.id}
                <div class="website-menu">
                  <button class="menu-item" on:click={() => handlePin(site)}>
                    {#if site.pinned}
                      <PinOff size={14} />
                      <span>Unpin</span>
                    {:else}
                      <Pin size={14} />
                      <span>Pin</span>
                    {/if}
                  </button>
                  <button class="menu-item" on:click={() => openRenameDialog(site)}>
                    <Pencil size={14} />
                    <span>Rename</span>
                  </button>
                  <button class="menu-item" on:click={() => handleDownload(site)}>
                    <Download size={14} />
                    <span>Download</span>
                  </button>
                  <button class="menu-item" on:click={() => handleArchive(site)}>
                    <Archive size={14} />
                    <span>{isArchived(site) ? 'Unarchive' : 'Archive'}</span>
                  </button>
                  <button class="menu-item delete" on:click={() => openDeleteDialog(site)}>
                    <Trash2 size={14} />
                    <span>Delete</span>
                  </button>
                </div>
              {/if}
            </div>
          {/each}
        </div>
      {/if}
    </div>

    <div class="websites-block">
      <div class="websites-block-title">Websites</div>
      {#if mainItems.length === 0}
        <div class="websites-empty">No websites saved</div>
      {:else}
        <div class="websites-list">
          {#each mainItems as site (site.id)}
            <div class="website-item">
              <button class="website-main" on:click={() => websitesStore.loadById(site.id)}>
              <span class="website-icon">
                <Globe />
              </span>
              <div class="website-text">
                <span class="website-title">{site.title}</span>
                <span class="website-domain">{formatDomain(site.domain)}</span>
              </div>
              </button>
              <button class="website-menu-btn" on:click={(event) => openMenu(event, site)} aria-label="More options">
                <MoreVertical size={14} />
              </button>
              {#if activeMenuId === site.id}
                <div class="website-menu">
                  <button class="menu-item" on:click={() => handlePin(site)}>
                    {#if site.pinned}
                      <PinOff size={14} />
                      <span>Unpin</span>
                    {:else}
                      <Pin size={14} />
                      <span>Pin</span>
                    {/if}
                  </button>
                  <button class="menu-item" on:click={() => openRenameDialog(site)}>
                    <Pencil size={14} />
                    <span>Rename</span>
                  </button>
                  <button class="menu-item" on:click={() => handleDownload(site)}>
                    <Download size={14} />
                    <span>Download</span>
                  </button>
                  <button class="menu-item" on:click={() => handleArchive(site)}>
                    <Archive size={14} />
                    <span>{isArchived(site) ? 'Unarchive' : 'Archive'}</span>
                  </button>
                  <button class="menu-item delete" on:click={() => openDeleteDialog(site)}>
                    <Trash2 size={14} />
                    <span>Delete</span>
                  </button>
                </div>
              {/if}
            </div>
          {/each}
        </div>
      {/if}
    </div>

    <div class="websites-block websites-archive">
      <Collapsible.Root defaultOpen={false} class="group/collapsible" data-collapsible-root>
        <div data-slot="sidebar-group" data-sidebar="group" class="relative flex w-full min-w-0 flex-col p-2">
          <Collapsible.Trigger
            data-slot="sidebar-group-label"
            data-sidebar="group-label"
            class="archive-trigger"
          >
            <span class="websites-block-title archive-label">Archive</span>
            <ChevronRight class="archive-chevron transition-transform group-data-[state=open]/collapsible:rotate-90" />
          </Collapsible.Trigger>
          <Collapsible.Content data-slot="collapsible-content" class="pt-1">
            <div data-slot="sidebar-group-content" data-sidebar="group-content" class="w-full text-sm">
              {#if archivedItems.length === 0}
                <div class="websites-empty">No archived websites</div>
              {:else}
                <div class="websites-list">
                  {#each archivedItems as site (site.id)}
                    <div class="website-item">
                      <button class="website-main" on:click={() => websitesStore.loadById(site.id)}>
                      <span class="website-icon">
                        <Globe />
                      </span>
                      <div class="website-text">
                        <span class="website-title">{site.title}</span>
                        <span class="website-domain">{formatDomain(site.domain)}</span>
                      </div>
                      </button>
                      <button class="website-menu-btn" on:click={(event) => openMenu(event, site)} aria-label="More options">
                        <MoreVertical size={14} />
                      </button>
                      {#if activeMenuId === site.id}
                        <div class="website-menu">
                          <button class="menu-item" on:click={() => handlePin(site)}>
                            {#if site.pinned}
                              <PinOff size={14} />
                              <span>Unpin</span>
                            {:else}
                              <Pin size={14} />
                              <span>Pin</span>
                            {/if}
                          </button>
                          <button class="menu-item" on:click={() => openRenameDialog(site)}>
                            <Pencil size={14} />
                            <span>Rename</span>
                          </button>
                          <button class="menu-item" on:click={() => handleDownload(site)}>
                            <Download size={14} />
                            <span>Download</span>
                          </button>
                          <button class="menu-item" on:click={() => handleArchive(site)}>
                            <Archive size={14} />
                            <span>{isArchived(site) ? 'Unarchive' : 'Archive'}</span>
                          </button>
                          <button class="menu-item delete" on:click={() => openDeleteDialog(site)}>
                            <Trash2 size={14} />
                            <span>Delete</span>
                          </button>
                        </div>
                      {/if}
                    </div>
                  {/each}
                </div>
              {/if}
            </div>
          </Collapsible.Content>
        </div>
      </Collapsible.Root>
    </div>
  {/if}
</div>

<style>
  .websites-sections {
    display: flex;
    flex-direction: column;
    gap: 1rem;
    flex: 1;
    min-height: 0;
    padding-top: 0;
  }

  .websites-block {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .websites-block:first-child {
    margin-top: 0.5rem;
  }

  .websites-archive {
    margin-top: auto;
  }

  .websites-block-title {
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--color-muted-foreground);
    font-weight: 600;
    padding: 0 0.25rem;
  }

  .websites-list {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    padding: 0 0.25rem;
  }

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
    font-size: 0.8rem;
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

  .websites-empty {
    font-size: 0.8rem;
    color: var(--color-muted-foreground);
    padding: 0.5rem 0.25rem;
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
</style>
