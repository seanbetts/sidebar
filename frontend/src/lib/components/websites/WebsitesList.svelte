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
      <a class="website-item" href={site.url} target="_blank" rel="noopener noreferrer">
        <Globe size={14} />
        <div class="website-text">
          <span class="website-title">{site.title}</span>
          <span class="website-domain">{site.domain}</span>
        </div>
      </a>
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
    text-decoration: none;
    color: var(--color-sidebar-foreground);
    background: transparent;
    transition: background-color 0.2s ease;
  }

  .website-item:hover {
    background-color: var(--color-sidebar-accent);
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
