<script lang="ts">
  import { thingsStore, type ThingsSelection } from '$lib/stores/things';
  import SidebarSectionHeader from '$lib/components/left-sidebar/SidebarSectionHeader.svelte';
  import { Button } from '$lib/components/ui/button';
  import { CalendarCheck, CalendarClock, Inbox, Layers, List, Plus } from 'lucide-svelte';

  let selection: ThingsSelection = { type: 'today' };
  let tasksCount = 0;
  let areas: Array<{ id: string; title: string }> = [];
  let projects: Array<{ id: string; title: string; areaId?: string | null }> = [];
  let isLoading = false;
  let error = '';

  $: ({ selection, areas, projects, isLoading, error } = $thingsStore);
  $: tasksCount = $thingsStore.tasks.length;
  $: projectsByArea = areas.map((area) => ({
    area,
    projects: projects.filter((project) => project.areaId === area.id)
  }));
  $: orphanProjects = projects.filter((project) => !project.areaId);

  function handleNewTask() {
    // TODO: wire task creation
  }

  function select(selection: ThingsSelection) {
    thingsStore.load(selection);
  }
</script>

<div class="things-panel">
  <SidebarSectionHeader title="Tasks">
    <svelte:fragment slot="actions">
      <Button
        size="icon"
        variant="ghost"
        class="panel-action"
        onclick={handleNewTask}
        aria-label="New task"
        title="New task"
      >
        <Plus size={16} />
      </Button>
    </svelte:fragment>
  </SidebarSectionHeader>
  <div class="things-sections">
    <button
      class="things-item"
      class:active={selection.type === 'inbox'}
      onclick={() => select({ type: 'inbox' })}
    >
      <span class="row-label">
        <Inbox size={14} />
        Inbox
      </span>
    </button>
    <button
      class="things-item"
      class:active={selection.type === 'today'}
      onclick={() => select({ type: 'today' })}
    >
      <span class="row-label">
        <CalendarCheck size={14} />
        Today
      </span>
      <span class="meta">{selection.type === 'today' ? tasksCount : ''}</span>
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
    </button>
    <div class="things-section-label">Areas</div>
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
        </button>
      {/each}
    {/if}
  </div>
  {#if error}
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
