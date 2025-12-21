<script lang="ts">
  import { ChevronDown, ChevronRight } from 'lucide-svelte';
  import { slide } from 'svelte/transition';

  export let title: string;
  export let defaultExpanded: boolean = true;
  export let icon: any = undefined;

  let isExpanded = defaultExpanded;

  function toggle() {
    isExpanded = !isExpanded;
  }
</script>

<div class="collapsible-section">
  <button class="section-header" on:click={toggle}>
    <div class="header-left">
      {#if icon}
        <svelte:component this={icon} size={18} />
      {/if}
      <span class="title">{title}</span>
    </div>
    <div class="chevron">
      {#if isExpanded}
        <ChevronDown size={16} />
      {:else}
        <ChevronRight size={16} />
      {/if}
    </div>
  </button>

  {#if isExpanded}
    <div class="section-content" transition:slide={{ duration: 200 }}>
      <slot />
    </div>
  {/if}
</div>

<style>
  .collapsible-section {
    display: flex;
    flex-direction: column;
    border-bottom: 1px solid var(--color-sidebar-border);
  }

  .section-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.75rem 1rem;
    background: none;
    border: none;
    cursor: pointer;
    transition: background-color 0.2s;
    color: var(--color-sidebar-foreground);
    width: 100%;
  }

  .section-header:hover {
    background-color: var(--color-sidebar-accent);
  }

  .header-left {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .title {
    font-weight: 600;
    font-size: 0.875rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .chevron {
    display: flex;
    align-items: center;
    color: var(--color-muted-foreground);
  }

  .section-content {
    overflow: hidden;
  }
</style>
