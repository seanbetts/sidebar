<script lang="ts">
  import { onMount } from 'svelte';
  import { thingsStore, type ThingsSelection } from '$lib/stores/things';
  import { CalendarCheck, CalendarClock, Check, Layers, List } from 'lucide-svelte';

  let selection: ThingsSelection = { type: 'today' };
  let tasksCount = 0;
  let counts: Record<string, number> = {};
  let areas: Array<{ id: string; title: string }> = [];
  let projects: Array<{ id: string; title: string; areaId?: string | null }> = [];
  let diagnostics = null;
  let error = '';

  $: ({ selection, areas, projects, error, counts, diagnostics } = $thingsStore);
  $: tasksCount = $thingsStore.todayCount;
  $: projectsByArea = areas.map((area) => ({
    area,
    projects: projects.filter((project) => project.areaId === area.id)
  }));
  $: orphanProjects = projects.filter((project) => !project.areaId);

  function select(selection: ThingsSelection) {
    thingsStore.load(selection);
    thingsStore.loadDiagnostics();
  }

  onMount(() => {
    thingsStore.loadCounts();
    thingsStore.loadDiagnostics();
  });
</script>

<div class="things-sections">
    <button
      class="things-item"
      class:active={selection.type === 'today'}
      onclick={() => select({ type: 'today' })}
    >
      <span class="row-label">
        <CalendarCheck size={14} />
        Today
      </span>
      <span class="meta">
        {#if tasksCount === 0}
          <Check size={12} />
        {:else}
          {tasksCount}
        {/if}
      </span>
    </button>
    <button
      class="things-item"
      class:active={selection.type === 'upcoming'}
      onclick={() => select({ type: 'upcoming' })}
    >
      <span class="row-label">
        <CalendarClock size={14} />
        Upcoming
      </span>
      <span class="meta">
        {#if (counts['upcoming'] ?? 0) === 0}
          <Check size={12} />
        {:else}
          {counts['upcoming'] ?? 0}
        {/if}
      </span>
    </button>
    <div class="things-divider"></div>
    {#if projectsByArea.length === 0}
      <div class="things-empty">No areas</div>
    {:else}
      {#each projectsByArea as group}
        <button
          class="things-item area-item"
          class:active={selection.type === 'area' && selection.id === group.area.id}
          onclick={() => select({ type: 'area', id: group.area.id })}
        >
          <span class="row-label">
            <Layers size={14} />
            {group.area.title}
          </span>
          <span class="meta">
            {#if (counts[`area:${group.area.id}`] ?? 0) === 0}
              <Check size={12} />
            {:else}
              {counts[`area:${group.area.id}`] ?? 0}
            {/if}
          </span>
        </button>
        {#each group.projects as project}
          <button
            class="things-item project-item"
            class:active={selection.type === 'project' && selection.id === project.id}
            onclick={() => select({ type: 'project', id: project.id })}
          >
            <span class="row-label">
              <List size={14} />
              {project.title}
            </span>
            <span class="meta">
              {#if (counts[`project:${project.id}`] ?? 0) === 0}
                <Check size={12} />
              {:else}
                {counts[`project:${project.id}`] ?? 0}
              {/if}
            </span>
          </button>
        {/each}
      {/each}
    {/if}
    {#if orphanProjects.length > 0}
      <div class="things-section-label">Projects</div>
      {#each orphanProjects as project}
        <button
          class="things-item project-item"
          class:active={selection.type === 'project' && selection.id === project.id}
          onclick={() => select({ type: 'project', id: project.id })}
        >
          <span class="row-label">
            <List size={14} />
            {project.title}
          </span>
          <span class="meta">
            {#if (counts[`project:${project.id}`] ?? 0) === 0}
              <Check size={12} />
            {:else}
              {counts[`project:${project.id}`] ?? 0}
            {/if}
          </span>
        </button>
      {/each}
    {/if}
  {#if diagnostics && !diagnostics.dbAccess}
    <div class="things-diagnostics">
      Things bridge running without Things DB access. Repeating task metadata unavailable.
    </div>
  {/if}
</div>

<style>
  .things-sections {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    gap: 0.35rem;
    padding: 0.75rem 0.5rem 0.5rem;
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

  .row-label {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
  }

  .area-item {
    font-weight: 600;
  }

  .project-item {
    padding-left: 1.6rem;
  }

  .things-section-label {
    font-size: 0.7rem;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--color-muted-foreground);
    margin-top: 0.4rem;
  }

  .things-divider {
    height: 1px;
    background: var(--color-sidebar-border);
    margin: 0.5rem 0.25rem 0.35rem;
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

  .things-diagnostics {
    margin-top: auto;
    padding: 0.6rem 0.5rem 0.2rem;
    font-size: 0.72rem;
    color: var(--color-muted-foreground);
  }

  .meta {
    font-size: 0.75rem;
    color: var(--color-muted-foreground);
  }
</style>
