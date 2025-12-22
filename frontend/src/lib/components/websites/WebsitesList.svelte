<script lang="ts">
  import { onMount } from 'svelte';
  import { Globe } from 'lucide-svelte';
  import { websitesStore } from '$lib/stores/websites';

  let isLoading = false;

  onMount(async () => {
    isLoading = true;
    await websitesStore.load();
    isLoading = false;
  });
</script>

<div class="websites-list">
  {#if $websitesStore.error}
    <div class="websites-empty">{$websitesStore.error}</div>
  {:else if isLoading}
    <div class="websites-empty">Loading websites...</div>
  {:else if $websitesStore.items.length === 0}
    <div class="websites-empty">No websites saved</div>
  {:else}
    {#each $websitesStore.items as site (site.id)}
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
  {/if}
</div>

<style>
  .websites-list {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    padding: 0.5rem 0.75rem 0.75rem;
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
</style>
