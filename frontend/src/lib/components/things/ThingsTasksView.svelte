<script lang="ts">
  import { thingsStore } from '$lib/stores/things';
  import { Check } from 'lucide-svelte';

  let tasks = [];
  let selectionLabel = 'Today';
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
    } else if (state.selection.type === 'upcoming') {
      selectionLabel = 'Upcoming';
    } else if (state.selection.type === 'area') {
      selectionLabel = areas.find((area) => area.id === state.selection.id)?.title || 'Area';
    } else if (state.selection.type === 'project') {
      selectionLabel = projects.find((project) => project.id === state.selection.id)?.title || 'Project';
    } else {
      selectionLabel = 'Tasks';
    }
  }

  async function handleComplete(taskId: string) {
    await thingsStore.completeTask(taskId);
  }
</script>

<div class="things-view">
  <div class="things-view-header">
    <h2>{selectionLabel}</h2>
    <span class="count">{tasks.length}</span>
  </div>

  {#if isLoading}
    <div class="things-state">Loading tasks…</div>
  {:else if error}
    <div class="things-error">{error}</div>
  {:else if tasks.length === 0}
    <div class="things-state">No tasks to show.</div>
  {:else}
    <ul class="things-list">
      {#each tasks as task}
        <li class="things-task">
          <button class="check" onclick={() => handleComplete(task.id)} aria-label="Complete task">
            <Check size={14} />
          </button>
          <div class="content">
            <div class="title">{task.title}</div>
            {#if task.deadline}
              <div class="meta">Due {task.deadline.slice(0, 10)}</div>
            {/if}
          </div>
        </li>
      {/each}
    </ul>
  {/if}
</div>

<style>
  .things-view {
    display: flex;
    flex-direction: column;
    height: 100%;
    padding: 1.5rem 2rem;
    gap: 1rem;
  }

  .things-view-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .things-view-header h2 {
    font-size: 1.4rem;
    font-weight: 600;
    margin: 0;
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

  .title {
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
  }

  .things-error {
    color: #d55b5b;
  }
</style>
