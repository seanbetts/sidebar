<script lang="ts">
  import { thingsStore } from '$lib/stores/things';
  import { Check, CalendarCheck, CalendarClock, Inbox, Layers, List } from 'lucide-svelte';

  let tasks = [];
  let selectionLabel = 'Today';
  let titleIcon = CalendarCheck;
  let areas = [];
  let projects = [];
  let isLoading = false;
  let error = '';

  $: {
    const state = $thingsStore;
    tasks = state.tasks;
    areas = state.areas;
    projects = state.projects;
    isLoading = state.isLoading;
    error = state.error;
    if (state.selection.type === 'today') {
      selectionLabel = 'Today';
      titleIcon = CalendarCheck;
    } else if (state.selection.type === 'upcoming') {
      selectionLabel = 'Upcoming';
      titleIcon = CalendarClock;
    } else if (state.selection.type === 'inbox') {
      selectionLabel = 'Inbox';
      titleIcon = Inbox;
    } else if (state.selection.type === 'area') {
      selectionLabel = areas.find((area) => area.id === state.selection.id)?.title || 'Area';
      titleIcon = Layers;
    } else if (state.selection.type === 'project') {
      selectionLabel = projects.find((project) => project.id === state.selection.id)?.title || 'Project';
      titleIcon = List;
    } else {
      selectionLabel = 'Tasks';
    }
  }

  async function handleComplete(taskId: string) {
    await thingsStore.completeTask(taskId);
  }
</script>

<div class="things-view">
  <div class="things-view-titlebar">
    <div class="title">
      <svelte:component this={titleIcon} size={18} />
      <span>{selectionLabel}</span>
    </div>
    <span class="count">{tasks.length}</span>
  </div>

  {#if isLoading}
    <div class="things-state">Loading tasks…</div>
  {:else if error}
    <div class="things-error">{error}</div>
  {:else if tasks.length === 0}
    <div class="things-state">
      {#if selectionLabel === 'Today'}
        All done for the day
      {:else}
        No tasks to show.
      {/if}
    </div>
  {:else}
    <div class="things-content">
      <ul class="things-list">
        {#each tasks as task}
          <li class="things-task">
            <button class="check" onclick={() => handleComplete(task.id)} aria-label="Complete task">
              <Check size={14} />
            </button>
            <div class="content">
              <div class="task-title">{task.title}</div>
              {#if task.deadline}
                <div class="meta">Due {task.deadline.slice(0, 10)}</div>
              {/if}
            </div>
          </li>
        {/each}
      </ul>
    </div>
  {/if}
</div>

<style>
  .things-view {
    display: flex;
    flex-direction: column;
    height: 100%;
    padding: 0;
    gap: 1rem;
  }

  .things-view-titlebar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1.25rem 2rem 1rem;
    border-bottom: 1px solid var(--color-border);
    background: var(--color-card);
  }

  .title {
    display: inline-flex;
    align-items: center;
    gap: 0.6rem;
    font-size: 1.1rem;
    font-weight: 600;
    letter-spacing: 0.01em;
  }

  .count {
    font-size: 0.9rem;
    color: var(--color-muted-foreground);
  }

  .things-list {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    padding: 1.5rem 0;
  }

  .things-content {
    max-width: 720px;
    width: 100%;
    margin: 0 2rem;
  }

  .things-task {
    display: flex;
    align-items: flex-start;
    gap: 0.75rem;
    padding: 0.6rem 0.75rem;
    border: 1px solid var(--color-border);
    border-radius: 0.75rem;
    background: var(--color-card);
  }

  .check {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 26px;
    height: 26px;
    border-radius: 999px;
    border: 1px solid var(--color-border);
    background: transparent;
    color: var(--color-muted-foreground);
    cursor: pointer;
  }

  .check:hover {
    color: var(--color-foreground);
    border-color: var(--color-foreground);
  }

  .task-title {
    font-size: 0.95rem;
    font-weight: 500;
  }

  .meta {
    font-size: 0.75rem;
    color: var(--color-muted-foreground);
    margin-top: 0.15rem;
  }

  .things-state {
    color: var(--color-muted-foreground);
    padding: 1.5rem 2rem;
    max-width: 720px;
  }

  .things-error {
    color: #d55b5b;
  }
</style>
