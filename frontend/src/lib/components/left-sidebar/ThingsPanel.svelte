<script lang="ts">
  import { thingsStore, type ThingsSelection } from '$lib/stores/things';
  import SidebarSectionHeader from '$lib/components/left-sidebar/SidebarSectionHeader.svelte';

  let selection: ThingsSelection = { type: 'today' };
  let tasksCount = 0;
  let areas: Array<{ id: string; title: string }> = [];
  let projects: Array<{ id: string; title: string; areaId?: string | null }> = [];
  let isLoading = false;
  let error = '';

  $: ({ selection, areas, projects, isLoading, error } = $thingsStore);
  $: tasksCount = $thingsStore.tasks.length;

  function select(selection: ThingsSelection) {
    thingsStore.load(selection);
  }
</script>

<div class="things-panel">
  <SidebarSectionHeader title="Things" />
  <div class="things-sections">
    <button
      class="things-item"
      class:active={selection.type === 'today'}
      onclick={() => select({ type: 'today' })}
    >
      Today
      <span class="meta">{selection.type === 'today' ? tasksCount : ''}</span>
    </button>
    <button
      class="things-item"
      class:active={selection.type === 'upcoming'}
      onclick={() => select({ type: 'upcoming' })}
    >
      Upcoming
    </button>
    <div class="things-section-label">Areas</div>
    {#if areas.length === 0}
      <div class="things-empty">No areas</div>
    {:else}
      {#each areas as area}
        <button
          class="things-item"
          class:active={selection.type === 'area' && selection.id === area.id}
          onclick={() => select({ type: 'area', id: area.id })}
        >
          {area.title}
        </button>
      {/each}
    {/if}
    <div class="things-section-label">Projects</div>
    {#if projects.length === 0}
      <div class="things-empty">No projects</div>
    {:else}
      {#each projects as project}
        <button
          class="things-item"
          class:active={selection.type === 'project' && selection.id === project.id}
          onclick={() => select({ type: 'project', id: project.id })}
        >
          {project.title}
        </button>
      {/each}
    {/if}
  </div>
  {#if isLoading}
    <div class="things-meta">Loading…</div>
  {:else if error}
    <div class="things-error">{error}</div>
  {/if}
</div>

<style>
  .things-panel {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
    gap: 0.75rem;
    padding: 0.75rem 0.5rem 0.5rem;
  }

  .things-sections {
    display: flex;
    flex-direction: column;
    overflow-y: auto;
    min-height: 0;
    gap: 0.35rem;
  }

  .things-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.5rem;
    padding: 0.4rem 0.5rem;
    border-radius: 0.5rem;
    border: 1px solid transparent;
    background: transparent;
    color: var(--color-sidebar-foreground);
    cursor: pointer;
    font-size: 0.85rem;
  }

  .things-item:hover {
    background: var(--color-sidebar-accent);
  }

  .things-item.active {
    background: var(--color-sidebar-accent);
    border-color: var(--color-sidebar-border);
  }

  .things-section-label {
    font-size: 0.7rem;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--color-muted-foreground);
    margin-top: 0.4rem;
  }

  .things-empty {
    font-size: 0.8rem;
    color: var(--color-muted-foreground);
    padding-left: 0.5rem;
  }

  .things-meta {
    font-size: 0.8rem;
    color: var(--color-muted-foreground);
  }

  .things-error {
    font-size: 0.8rem;
    color: #d55b5b;
  }

  .meta {
    font-size: 0.75rem;
    color: var(--color-muted-foreground);
  }
</style>
