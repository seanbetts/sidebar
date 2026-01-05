<script lang="ts">
  import type { ThingsArea, ThingsProject, ThingsTask } from '$lib/types/things';
  import { List, Search } from 'lucide-svelte';
  import ThingsDraftForm from './ThingsDraftForm.svelte';
  import ThingsTaskList from './ThingsTaskList.svelte';

  export type ThingsTaskViewType = 'inbox' | 'today' | 'upcoming' | 'area' | 'project' | 'search';

  export let tasks: ThingsTask[] = [];
  export let sections: { id: string; title: string; tasks: ThingsTask[] }[] = [];
  export let selectionType: ThingsTaskViewType = 'today';
  export let selectionLabel = 'Today';
  export let selectionQuery = '';
  export let isLoading = false;
  export let searchPending = false;
  export let error = '';

  export let showDraft = false;
  export let draftTitle = '';
  export let draftNotes = '';
  export let draftDueDate = '';
  export let draftSaving = false;
  export let draftError = '';
  export let draftTargetLabel = '';
  export let draftListId = '';
  export let titleInput: HTMLInputElement | null = null;
  export let areaOptions: ThingsArea[] = [];
  export let projectsByArea: Map<string, ThingsProject[]> = new Map();
  export let orphanProjects: ThingsProject[] = [];

  export let busyTasks: Set<string> = new Set();
  export let editingTaskId: string | null = null;
  export let renameValue = '';
  export let renameInput: HTMLInputElement | null = null;

  export let onDraftInput: () => void;
  export let onCreateTask: () => void;
  export let onCancelDraft: () => void;
  export let onDraftListChange: (value: string) => void;

  export let onComplete: (taskId: string) => void;
  export let onStartRename: (task: ThingsTask) => void;
  export let onCommitRename: (task: ThingsTask) => void;
  export let onCancelRename: () => void;
  export let onOpenNotes: (task: ThingsTask) => void;
  export let onOpenMove: (task: ThingsTask) => void;
  export let onOpenDue: (task: ThingsTask) => void;
  export let onOpenTrash: (task: ThingsTask) => void;
  export let onDefer: (task: ThingsTask, days: number) => void;
  export let onDeferToWeekday: (task: ThingsTask, targetDay: number) => void;
  export let onSetDueToday: (task: ThingsTask) => void;

  export let taskSubtitle: (task: ThingsTask) => string;
  export let dueLabel: (task: ThingsTask) => string | null;
</script>

{#if isLoading || (selectionType === 'search' && searchPending)}
  <div class="things-state">
    {#if selectionType === 'search'}
      <Search size={28} class="things-loading-icon" />
    {:else}
      <List size={28} class="things-loading-icon" />
    {/if}
    {#if selectionType === 'search'}
      Loading search results…
    {:else}
      Loading tasks…
    {/if}
  </div>
{:else if error}
  <div class="things-error">{error}</div>
{:else}
  <div class="things-content">
    {#if showDraft}
      <ThingsDraftForm
        bind:draftTitle
        bind:draftNotes
        bind:draftDueDate
        bind:draftListId
        bind:titleInput
        draftSaving={draftSaving}
        draftError={draftError}
        draftTargetLabel={draftTargetLabel}
        areaOptions={areaOptions}
        projectsByArea={projectsByArea}
        orphanProjects={orphanProjects}
        onDraftInput={onDraftInput}
        onCreateTask={onCreateTask}
        onCancelDraft={onCancelDraft}
        onDraftListChange={onDraftListChange}
      />
    {/if}
    {#if tasks.length === 0}
      <div class="things-state">
        <img class="things-empty-logo" src="/images/logo.svg" alt="sideBar" />
        {#if selectionLabel === 'Today'}
          All done for the day
        {:else if selectionType === 'search'}
          No results for "{selectionQuery}"
        {:else}
          No tasks to show.
        {/if}
      </div>
    {:else}
      <ThingsTaskList
        sections={sections}
        selectionType={selectionType}
        busyTasks={busyTasks}
        editingTaskId={editingTaskId}
        bind:renameValue
        bind:renameInput
        onComplete={onComplete}
        onStartRename={onStartRename}
        onCommitRename={onCommitRename}
        onCancelRename={onCancelRename}
        onOpenNotes={onOpenNotes}
        onOpenMove={onOpenMove}
        onOpenDue={onOpenDue}
        onOpenTrash={onOpenTrash}
        onDefer={onDefer}
        onDeferToWeekday={onDeferToWeekday}
        onSetDueToday={onSetDueToday}
        taskSubtitle={taskSubtitle}
        dueLabel={dueLabel}
      />
    {/if}
  </div>
{/if}

<style>
  .things-content {
    max-width: 720px;
    width: 100%;
    margin: 0 auto;
    padding: 1.5rem 2rem 2rem;
    display: flex;
    flex-direction: column;
    gap: 1.25rem;
  }

  .things-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    color: var(--color-muted-foreground);
    padding: 1.5rem 2rem;
    max-width: 720px;
    margin: 0 auto;
  }

  .things-empty-logo {
    height: 3.25rem;
    width: auto;
    margin-bottom: 0.75rem;
    opacity: 0.7;
  }

  :global(.dark) .things-empty-logo {
    filter: invert(1);
  }

  :global(.things-loading-icon) {
    margin-bottom: 0.6rem;
    opacity: 0.7;
  }

  .things-error {
    color: #d55b5b;
    padding: 1.5rem 2rem;
    max-width: 720px;
    margin: 0 auto;
  }
</style>
