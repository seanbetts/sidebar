<script lang="ts">
  import { onMount } from 'svelte';
  import { ChevronRight, Globe } from 'lucide-svelte';
  import * as Collapsible from '$lib/components/ui/collapsible/index.js';
  import { websitesStore } from '$lib/stores/websites';
  import type { WebsiteItem } from '$lib/stores/websites';

  const ARCHIVED_FLAG = 'archived';

  onMount(async () => {
    if ($websitesStore.items.length === 0 && !$websitesStore.loading) {
      await websitesStore.load();
    }
  });

  function isArchived(site: WebsiteItem) {
    return Boolean((site as WebsiteItem & Record<string, unknown>)[ARCHIVED_FLAG]);
  }

  $: pinnedItems = $websitesStore.items.filter((site) => site.pinned && !isArchived(site));
  $: mainItems = $websitesStore.items.filter((site) => !site.pinned && !isArchived(site));
  $: archivedItems = $websitesStore.items.filter((site) => isArchived(site));
</script>

<div class="websites-sections">
  <div class="websites-block">
    <div class="websites-block-title">Pinned</div>
    {#if $websitesStore.error}
      <div class="websites-empty">{$websitesStore.error}</div>
    {:else if $websitesStore.loading}
      <div class="websites-empty">Loading websites...</div>
    {:else if pinnedItems.length === 0}
      <div class="websites-empty">No pinned websites</div>
    {:else}
      <div class="websites-list">
        {#each pinnedItems as site (site.id)}
          <button class="website-item" on:click={() => websitesStore.loadById(site.id)}>
            <span class="website-icon">
              <Globe />
            </span>
            <div class="website-text">
              <span class="website-title">{site.title}</span>
              <span class="website-domain">{site.domain}</span>
            </div>
          </button>
        {/each}
      </div>
    {/if}
  </div>

  <div class="websites-block">
    <div class="websites-block-title">Websites</div>
    {#if $websitesStore.error}
      <div class="websites-empty">{$websitesStore.error}</div>
    {:else if $websitesStore.loading}
      <div class="websites-empty">Loading websites...</div>
    {:else if mainItems.length === 0}
      <div class="websites-empty">No websites saved</div>
    {:else}
      <div class="websites-list">
        {#each mainItems as site (site.id)}
          <button class="website-item" on:click={() => websitesStore.loadById(site.id)}>
            <span class="website-icon">
              <Globe />
            </span>
            <div class="website-text">
              <span class="website-title">{site.title}</span>
              <span class="website-domain">{site.domain}</span>
            </div>
          </button>
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
            {#if $websitesStore.error}
              <div class="websites-empty">{$websitesStore.error}</div>
            {:else if $websitesStore.loading}
              <div class="websites-empty">Loading websites...</div>
            {:else if archivedItems.length === 0}
              <div class="websites-empty">No archived websites</div>
            {:else}
              <div class="websites-list">
                {#each archivedItems as site (site.id)}
                  <button class="website-item" on:click={() => websitesStore.loadById(site.id)}>
                    <span class="website-icon">
                      <Globe />
                    </span>
                    <div class="website-text">
                      <span class="website-title">{site.title}</span>
                      <span class="website-domain">{site.domain}</span>
                    </div>
                  </button>
                {/each}
              </div>
            {/if}
          </div>
        </Collapsible.Content>
      </div>
    </Collapsible.Root>
  </div>
</div>

<style>
  .websites-sections {
    display: flex;
    flex-direction: column;
    gap: 1rem;
    flex: 1;
    min-height: 0;
    padding-top: 0.5rem;
  }

  .websites-block {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
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
    cursor: pointer;
    transition: background-color 0.2s ease;
  }

  .website-item:hover {
    background-color: var(--color-sidebar-accent);
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
  }

  .website-title {
    font-size: 0.85rem;
    font-weight: 500;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
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
