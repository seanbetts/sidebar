<script lang="ts">
  import { onDestroy, tick } from 'svelte';
  import { ChevronRight, Globe, Search } from 'lucide-svelte';
  import * as Collapsible from '$lib/components/ui/collapsible/index.js';
  import SidebarLoading from '$lib/components/left-sidebar/SidebarLoading.svelte';
  import SidebarEmptyState from '$lib/components/left-sidebar/SidebarEmptyState.svelte';
  import { websitesStore } from '$lib/stores/websites';
  import type { WebsiteItem } from '$lib/stores/websites';
  import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';
  import DeleteDialogController from '$lib/components/files/DeleteDialogController.svelte';
  import WebsiteRow from '$lib/components/websites/WebsiteRow.svelte';
  import { useWebsiteActions } from '$lib/hooks/useWebsiteActions';

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
  $: pinnedItemsSorted = [...pinnedItems].sort((a, b) => {
    const aOrder = typeof a.pinned_order === 'number' ? a.pinned_order : Number.POSITIVE_INFINITY;
    const bOrder = typeof b.pinned_order === 'number' ? b.pinned_order : Number.POSITIVE_INFINITY;
    if (aOrder !== bOrder) return aOrder - bOrder;
    return (a.updated_at || '').localeCompare(b.updated_at || '');
  });
  $: mainItems = $websitesStore.items.filter((site) => !site.pinned && !isArchived(site));
  $: archivedItems = $websitesStore.items.filter((site) => isArchived(site));
  $: totalItems = $websitesStore.items.length;

  let activeMenuId: string | null = null;
  let menuTimeout: ReturnType<typeof setTimeout> | null = null;
  let removeOutsideListener: (() => void) | null = null;
  let isRenameDialogOpen = false;
  let renameValue = '';
  let renameInput: HTMLInputElement | null = null;
  let deleteDialog: { openDialog: (name: string) => void } | null = null;
  let selectedSite: WebsiteItem | null = null;
  const PINNED_DROP_END = '__end__';
  let draggingPinnedId: string | null = null;
  let dragOverPinnedId: string | null = null;
  const {
    openWebsite: openWebsiteById,
    renameWebsite,
    pinWebsite,
    archiveWebsite,
    deleteWebsite,
    updatePinnedOrder
  } = useWebsiteActions();

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

  async function openWebsite(site: WebsiteItem) {
    await openWebsiteById(site.id);
  }

  function handlePinnedDragStart(event: DragEvent, siteId: string) {
    draggingPinnedId = siteId;
    dragOverPinnedId = null;
    event.dataTransfer?.setData('text/plain', siteId);
    event.dataTransfer!.effectAllowed = 'move';
  }

  function handlePinnedDragOver(event: DragEvent, siteId: string) {
    if (!draggingPinnedId) return;
    event.preventDefault();
    dragOverPinnedId = siteId;
  }

  async function handlePinnedDrop(event: DragEvent, targetId: string) {
    if (!draggingPinnedId) return;
    event.preventDefault();
    const sourceId = draggingPinnedId;
    draggingPinnedId = null;
    dragOverPinnedId = null;
    if (sourceId === targetId) return;
    const order = pinnedItemsSorted.map(site => site.id);
    const fromIndex = order.indexOf(sourceId);
    const toIndex = order.indexOf(targetId);
    if (fromIndex === -1 || toIndex === -1) return;
    const nextOrder = [...order];
    nextOrder.splice(toIndex, 0, nextOrder.splice(fromIndex, 1)[0]);
    await updatePinnedOrder(nextOrder, { scope: 'websitesPanel.pinOrder' });
  }

  async function handlePinnedDropEnd(event: DragEvent) {
    if (!draggingPinnedId) return;
    event.preventDefault();
    const sourceId = draggingPinnedId;
    draggingPinnedId = null;
    dragOverPinnedId = null;
    const order = pinnedItemsSorted.map(site => site.id);
    const fromIndex = order.indexOf(sourceId);
    if (fromIndex === -1) return;
    const nextOrder = [...order];
    nextOrder.push(nextOrder.splice(fromIndex, 1)[0]);
    await updatePinnedOrder(nextOrder, { scope: 'websitesPanel.pinOrder' });
  }

  function handlePinnedDragEnd() {
    draggingPinnedId = null;
    dragOverPinnedId = null;
  }

  async function handleRename() {
    if (!selectedSite) return;
    const trimmed = renameValue.trim();
    if (!trimmed || trimmed === selectedSite.title) {
      isRenameDialogOpen = false;
      return;
    }
    const renamed = await renameWebsite(selectedSite.id, trimmed, {
      scope: 'websitesPanel.rename'
    });
    if (renamed) {
      isRenameDialogOpen = false;
    }
  }

  async function handlePin(site: WebsiteItem) {
    const pinned = await pinWebsite(site.id, !site.pinned, {
      scope: 'websitesPanel.pin'
    });
    if (pinned) {
      closeMenu();
    }
  }

  async function handleArchive(site: WebsiteItem) {
    const archived = await archiveWebsite(site.id, !isArchived(site), {
      scope: 'websitesPanel.archive'
    });
    if (archived) {
      closeMenu();
    }
  }

  function handleDownload(site: WebsiteItem) {
    const link = document.createElement('a');
    link.href = `/api/v1/websites/${site.id}/download`;
    link.download = `${site.title || 'website'}.md`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    closeMenu();
  }

  function openDeleteDialog(site: WebsiteItem) {
    selectedSite = site;
    deleteDialog?.openDialog(site.title || 'website');
    closeMenu();
  }

  async function handleDelete(): Promise<boolean> {
    if (!selectedSite) return false;
    const deleted = await deleteWebsite(selectedSite.id, {
      scope: 'websitesPanel.delete'
    });
    if (deleted) {
      selectedSite = null;
    }
    return deleted;
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
        onkeydown={(event) => {
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

<DeleteDialogController
  bind:this={deleteDialog}
  itemType="website"
  onConfirm={handleDelete}
/>

<div class="websites-sections">
  {#if $websitesStore.error}
    <SidebarEmptyState
      icon={Globe}
      title="Service unavailable"
      subtitle="Please try again later."
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
        <div class="websites-scroll-area">
          <div class="websites-list">
            {#each $websitesStore.items as site (site.id)}
              <WebsiteRow
                {site}
                archived={isArchived(site)}
                isMenuOpen={activeMenuId === site.id}
                formatDomain={formatDomain}
                onOpen={openWebsite}
                onOpenMenu={openMenu}
                onPin={handlePin}
                onRename={openRenameDialog}
                onDownload={handleDownload}
                onArchive={handleArchive}
                onDelete={openDeleteDialog}
              />
            {/each}
          </div>
        </div>
      {/if}
    </div>
  {:else}
    <div class="websites-block">
      <div class="websites-block-title">Pinned</div>
      {#if pinnedItemsSorted.length === 0}
        <div class="websites-empty">No pinned websites</div>
      {:else}
        <div class="websites-list">
          {#each pinnedItemsSorted as site (site.id)}
            <WebsiteRow
              {site}
              archived={isArchived(site)}
              isMenuOpen={activeMenuId === site.id}
              formatDomain={formatDomain}
              onOpen={openWebsite}
              onOpenMenu={openMenu}
              onPin={handlePin}
              onRename={openRenameDialog}
              onDownload={handleDownload}
              onArchive={handleArchive}
              onDelete={openDeleteDialog}
              showGrabHandle
              isDragOver={dragOverPinnedId === site.id}
              onGrabStart={(event) => handlePinnedDragStart(event, site.id)}
              onGrabOver={(event) => handlePinnedDragOver(event, site.id)}
              onGrabDrop={(event) => handlePinnedDrop(event, site.id)}
              onGrabEnd={handlePinnedDragEnd}
            />
          {/each}
          <div
            class="pinned-drop-zone"
            class:drag-over={dragOverPinnedId === PINNED_DROP_END}
            role="separator"
            aria-label="Drop pinned website at end"
            ondragover={(event) => handlePinnedDragOver(event, PINNED_DROP_END)}
            ondrop={handlePinnedDropEnd}
          ></div>
        </div>
      {/if}
    </div>

    <div class="websites-block websites-scroll-area">
      <div class="websites-block-title">Websites</div>
      {#if mainItems.length === 0}
        <div class="websites-empty">No websites saved</div>
      {:else}
        <div class="websites-list">
          {#each mainItems as site (site.id)}
            <WebsiteRow
              {site}
              archived={isArchived(site)}
              isMenuOpen={activeMenuId === site.id}
              formatDomain={formatDomain}
              onOpen={openWebsite}
              onOpenMenu={openMenu}
              onPin={handlePin}
              onRename={openRenameDialog}
              onDownload={handleDownload}
              onArchive={handleArchive}
              onDelete={openDeleteDialog}
            />
          {/each}
        </div>
      {/if}
    </div>

    <div class="websites-block websites-archive">
      <Collapsible.Root class="group/collapsible" data-collapsible-root>
        <div data-slot="sidebar-group" data-sidebar="group" class="relative flex w-full min-w-0 flex-col p-2">
          <Collapsible.Trigger
            data-slot="sidebar-group-label"
            data-sidebar="group-label"
            class="archive-trigger"
          >
            <span class="websites-block-title archive-label">Archive</span>
            <span class="archive-chevron transition-transform group-data-[state=open]/collapsible:rotate-90">
              <ChevronRight size={16} />
            </span>
          </Collapsible.Trigger>
          <Collapsible.Content data-slot="collapsible-content" class="websites-archive-content pt-1">
            <div data-slot="sidebar-group-content" data-sidebar="group-content" class="w-full text-sm">
              {#if archivedItems.length === 0}
                <div class="websites-empty">No archived websites</div>
              {:else}
                <div class="websites-list">
                  {#each archivedItems as site (site.id)}
                    <WebsiteRow
                      {site}
                      archived={isArchived(site)}
                      isMenuOpen={activeMenuId === site.id}
                      formatDomain={formatDomain}
                      onOpen={openWebsite}
                      onOpenMenu={openMenu}
                      onPin={handlePin}
                      onRename={openRenameDialog}
                      onDownload={handleDownload}
                      onArchive={handleArchive}
                      onDelete={openDeleteDialog}
                    />
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
    overflow: hidden;
    padding-right: 0.25rem;
    height: 100%;
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
    border-top: 1px solid var(--color-sidebar-border);
    padding-top: 0;
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

  .websites-scroll-area {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
    overflow-y: auto;
  }

  .pinned-drop-zone {
    position: relative;
    height: 12px;
  }

  .pinned-drop-zone.drag-over::before {
    content: '';
    position: absolute;
    left: 0.5rem;
    right: 0.5rem;
    bottom: 0;
    height: 2px;
    border-radius: 999px;
    background: var(--color-sidebar-border);
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
    padding: 1rem 0.25rem;
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

  :global(.archive-chevron) {
    width: 16px;
    height: 16px;
    flex-shrink: 0;
    color: var(--color-muted-foreground);
  }

  :global(.archive-trigger:hover) :global(.archive-chevron) {
    color: var(--color-foreground);
  }

  :global(.websites-archive-content) {
    max-height: min(80vh, 720px);
    overflow-y: auto;
    padding-right: 0.25rem;
  }
</style>
