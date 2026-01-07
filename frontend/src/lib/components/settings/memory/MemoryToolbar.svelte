<script lang="ts">
  import { Plus, Search } from 'lucide-svelte';
  import { onMount } from 'svelte';
  import { Tooltip, TooltipContent, TooltipTrigger } from '$lib/components/ui/tooltip';
  import { TOOLTIP_COPY } from '$lib/constants/tooltips';
  import { canShowTooltips } from '$lib/utils/tooltip';

  export let searchTerm = '';
  export let onCreate: () => void;

  let tooltipsEnabled = false;

  onMount(() => {
    tooltipsEnabled = canShowTooltips();
  });
</script>

<div class="memory-toolbar">
  <Tooltip disabled={!tooltipsEnabled}>
    <TooltipTrigger>
      {#snippet child({ props })}
        {@const { type: _type, ...restProps } = props}
        <div class="memory-search" {...restProps}>
          <Search size={14} />
          <input
            class="memory-search-input"
            type="text"
            placeholder="Search memories"
            bind:value={searchTerm}
          />
        </div>
      {/snippet}
    </TooltipTrigger>
    <TooltipContent side="top">{TOOLTIP_COPY.searchMemories}</TooltipContent>
  </Tooltip>
  <Tooltip disabled={!tooltipsEnabled}>
    <TooltipTrigger>
      {#snippet child({ props })}
        <button class="settings-button" on:click={onCreate} {...props}>
          <Plus size={14} />
          Add Memory
        </button>
      {/snippet}
    </TooltipTrigger>
    <TooltipContent side="top">{TOOLTIP_COPY.addMemory}</TooltipContent>
  </Tooltip>
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
