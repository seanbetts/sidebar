<script lang="ts">
  import { Search, X } from 'lucide-svelte';
  import { conversationListStore } from '$lib/stores/conversations';

  let searchQuery = '';
  let debounceTimeout: ReturnType<typeof setTimeout>;

  function handleSearch() {
    clearTimeout(debounceTimeout);
    debounceTimeout = setTimeout(async () => {
      await conversationListStore.search(searchQuery);
    }, 300); // 300ms debounce
  }

  function clearSearch() {
    searchQuery = '';
    conversationListStore.load();
  }

  $: if (searchQuery !== undefined) handleSearch();
</script>

<div class="search-bar">
  <div class="search-input-wrapper">
    <Search size={16} class="search-icon" />
    <input
      type="text"
      bind:value={searchQuery}
      placeholder="Search conversations..."
      class="search-input"
    />
    {#if searchQuery}
      <button on:click={clearSearch} class="clear-btn" aria-label="Clear search">
        <X size={16} />
      </button>
    {/if}
  </div>
</div>

<style>
  .search-bar {
    padding: 0 1rem 1rem 1rem;
  }

  .search-input-wrapper {
    position: relative;
    display: flex;
    align-items: center;
  }

  :global(.search-icon) {
    position: absolute;
    left: 0.75rem;
    color: var(--color-text-secondary, #666);
    pointer-events: none;
  }

  .search-input {
    width: 100%;
    padding: 0.5rem 0.75rem 0.5rem 2.5rem;
    border: 1px solid var(--color-border, #e0e0e0);
    border-radius: 0.375rem;
    font-size: 0.875rem;
    background-color: white;
    transition: border-color 0.2s;
  }

  .search-input:focus {
    outline: none;
    border-color: var(--color-primary, #000);
  }

  .clear-btn {
    position: absolute;
    right: 0.5rem;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0.25rem;
    background: none;
    border: none;
    cursor: pointer;
    border-radius: 0.25rem;
    color: var(--color-text-secondary, #666);
    transition: background-color 0.2s;
  }

  .clear-btn:hover {
    background-color: var(--color-background-hover, #f0f0f0);
  }
</style>
