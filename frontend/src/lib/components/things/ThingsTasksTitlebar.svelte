<script lang="ts">
  import { Check } from 'lucide-svelte';

  export let selectionLabel: string;
  export let titleIcon: any;
  export let totalCount: number;
  export let hasLoaded: boolean;
</script>

<div class="things-view-titlebar">
  <div class="title">
    <svelte:component this={titleIcon} size={20} />
    <span>{selectionLabel}</span>
  </div>
  {#if hasLoaded}
    <span class="count">
      {#if totalCount === 0}
        <Check size={16} />
      {:else}
        {totalCount} tasks
      {/if}
    </span>
  {/if}
</div>

<style>
  .things-view-titlebar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.5rem 1.5rem;
    min-height: 57px;
    border-bottom: 1px solid var(--color-border);
    background-color: var(--color-card);
  }

  .title {
    display: inline-flex;
    align-items: center;
    gap: 0.75rem;
    font-size: 1.125rem;
    font-weight: 600;
    line-height: 1.2;
  }

  .count {
    font-size: 0.9rem;
    color: var(--color-muted-foreground);
  }
</style>
