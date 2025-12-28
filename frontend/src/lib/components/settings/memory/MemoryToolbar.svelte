<script lang="ts">
  import { Plus, Search } from 'lucide-svelte';

  export let searchTerm = '';
  export let onCreate: () => void;
</script>

<div class="memory-toolbar">
  <div class="memory-search">
    <Search size={14} />
    <input
      class="memory-search-input"
      type="text"
      placeholder="Search memories"
      bind:value={searchTerm}
    />
  </div>
  <button class="settings-button" on:click={onCreate}>
    <Plus size={14} />
    Add Memory
  </button>
</div>

<style>
  .memory-toolbar {
    display: flex;
    gap: 0.75rem;
    align-items: center;
    justify-content: space-between;
  }

  .memory-search {
    flex: 1;
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.45rem 0.65rem;
    border-radius: 0.7rem;
    border: 1px solid var(--color-border);
    background: var(--color-card);
    color: var(--color-muted-foreground);
  }

  .memory-search-input {
    flex: 1;
    border: none;
    background: transparent;
    color: var(--color-foreground);
    font-size: 0.85rem;
    outline: none;
  }

  @media (max-width: 720px) {
    .memory-toolbar {
      flex-direction: column;
      align-items: stretch;
    }
  }
</style>
