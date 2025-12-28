<script lang="ts">
  import SearchBar from './SearchBar.svelte';

  export let title = '';
  export let searchPlaceholder = '';
  export let onSearch: (query: string) => void;
  export let onClear: () => void;
</script>

<div class="panel-section-header">
  <div class="panel-section-header-row">
    <div class="panel-section-title">{title}</div>
    <div class="panel-section-actions">
      <slot name="actions" />
    </div>
  </div>
  <SearchBar onSearch={onSearch} onClear={onClear} placeholder={searchPlaceholder} />
</div>

<style>
  .panel-section-header {
    display: flex;
    flex-direction: column;
    padding: 1rem;
    gap: 0.75rem;
    border-bottom: 1px solid var(--color-sidebar-border);
  }

  .panel-section-header-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.75rem;
  }

  .panel-section-title {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    font-weight: 600;
    font-size: 0.95rem;
    color: var(--color-sidebar-foreground);
  }

  .panel-section-actions {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
  }

  ::slotted(.panel-action) {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    padding: 0.25rem;
    border-radius: 0.5rem;
    border: 1px solid transparent;
    background-color: transparent;
    color: var(--color-sidebar-foreground);
    font-size: 0.75rem;
    cursor: pointer;
    transition: background-color 0.2s ease, border-color 0.2s ease;
  }

  ::slotted(.panel-action:hover) {
    background-color: var(--color-sidebar-accent);
  }
</style>
