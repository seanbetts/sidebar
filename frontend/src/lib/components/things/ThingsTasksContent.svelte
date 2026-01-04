<script lang="ts">
  import type { ThingsArea, ThingsProject, ThingsTask } from '$lib/types/things';
  import {
    CalendarCheck,
    CalendarClock,
    CalendarPlus,
    Circle,
    FileText,
    Layers,
    List,
    MoreHorizontal,
    Pencil,
    Repeat,
    Search,
    Trash2,
    Check
  } from 'lucide-svelte';
  import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuSeparator,
    DropdownMenuTrigger
  } from '$lib/components/ui/dropdown-menu';

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
      <div class="new-task-card">
        <div class="new-task-header">
          <span>New task</span>
          {#if draftTargetLabel}
            <span class="new-task-target">{draftTargetLabel}</span>
          {/if}
        </div>
        <input
          class="new-task-input"
          type="text"
          placeholder="Task title"
          bind:value={draftTitle}
          disabled={draftSaving}
          bind:this={titleInput}
          onkeydown={(event) => {
            if (event.key === 'Enter') {
              event.preventDefault();
              onCreateTask();
            }
          }}
          oninput={onDraftInput}
        />
        <div class="new-task-meta">
          <label class="new-task-label">
            <span>Due date</span>
            <input class="new-task-date" type="date" bind:value={draftDueDate} disabled={draftSaving} />
          </label>
          <label class="new-task-label">
            <span>Project</span>
            <select
              class="new-task-select"
              bind:value={draftListId}
              onchange={(event) => onDraftListChange((event.currentTarget as HTMLSelectElement).value)}
              disabled={draftSaving}
            >
              <option value="">Select area or project</option>
              {#each areaOptions as area}
                <option value={area.id}>{area.title}</option>
                {#each projectsByArea.get(area.id) ?? [] as project}
                  <option value={project.id}>- {project.title}</option>
                {/each}
              {/each}
              {#if orphanProjects.length}
                {#each orphanProjects as project}
                  <option value={project.id}>- {project.title}</option>
                {/each}
              {/if}
            </select>
          </label>
        </div>
        <textarea
          class="new-task-notes"
          rows="1"
          placeholder="Notes (optional)"
          bind:value={draftNotes}
          disabled={draftSaving}
        ></textarea>
        {#if draftError}
          <div class="new-task-error">{draftError}</div>
        {/if}
        <div class="new-task-actions">
          <button class="new-task-btn secondary" onclick={onCancelDraft} disabled={draftSaving}>
            Cancel
          </button>
          <button
            class="new-task-btn primary"
            onclick={onCreateTask}
            disabled={!draftTitle.trim() || !draftListId || draftSaving}
          >
            {draftSaving ? 'Adding…' : 'Add task'}
          </button>
        </div>
      </div>
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
      {#each sections as section}
        <div class="things-section">
          {#if section.title}
            <div class="things-section-title">{section.title}</div>
          {/if}
          <ul class="things-list">
            {#each section.tasks as task}
              <li class="things-task" class:completing={busyTasks.has(task.id)}>
                <div class="task-left">
                  {#if task.repeatTemplate}
                    <span class="repeat-badge" aria-label="Repeating task">
                      <Repeat size={14} />
                    </span>
                  {:else}
                    <button
                      class="check"
                      class:completing={busyTasks.has(task.id)}
                      onclick={() => onComplete(task.id)}
                      aria-label="Complete task"
                      disabled={busyTasks.has(task.id)}
                    >
                      {#if busyTasks.has(task.id)}
                        <Check size={14} />
                      {:else}
                        <Circle size={14} />
                      {/if}
                    </button>
                  {/if}
                  <div class="content">
                    <div class="task-title">
                      {#if editingTaskId === task.id}
                        <input
                          class="task-rename-input"
                          type="text"
                          bind:value={renameValue}
                          bind:this={renameInput}
                          onkeydown={(event) => {
                            if (event.key === 'Enter') {
                              event.preventDefault();
                              onCommitRename(task);
                            }
                            if (event.key === 'Escape') {
                              event.preventDefault();
                              onCancelRename();
                            }
                          }}
                          onblur={() => onCommitRename(task)}
                        />
                      {:else}
                        <span>{task.title}</span>
                      {/if}
                      {#if task.notes}
                        <span class="notes-icon" aria-label="Task notes">
                          <FileText size={14} />
                          <span class="notes-tooltip">{task.notes}</span>
                        </span>
                      {/if}
                      {#if task.repeating && !task.repeatTemplate}
                        <Repeat size={14} class="repeat-icon" />
                      {/if}
                    </div>
                    {#if taskSubtitle(task)}
                      <div class="meta">{taskSubtitle(task)}</div>
                    {/if}
                  </div>
                </div>
                <div class="task-right">
                  {#if selectionType === 'area' || selectionType === 'project' || selectionType === 'search'}
                    <span class="due-pill">{dueLabel(task) ?? 'No Date'}</span>
                  {/if}
                  <DropdownMenu>
                    <DropdownMenuTrigger
                      class="task-menu-btn"
                      aria-label="Task options"
                      disabled={task.repeatTemplate}
                    >
                      <MoreHorizontal size={16} />
                    </DropdownMenuTrigger>
                    <DropdownMenuContent class="task-menu" align="end" sideOffset={6}>
                      <DropdownMenuItem class="task-menu-item" onclick={() => onStartRename(task)}>
                        <Pencil size={14} />
                        Rename
                      </DropdownMenuItem>
                      <DropdownMenuItem class="task-menu-item" onclick={() => onOpenNotes(task)}>
                        <FileText size={14} />
                        Edit notes
                      </DropdownMenuItem>
                      <DropdownMenuItem class="task-menu-item" onclick={() => onOpenMove(task)}>
                        <Layers size={14} />
                        Move to…
                      </DropdownMenuItem>
                      <DropdownMenuSeparator />
                      {#if selectionType !== 'today'}
                        <DropdownMenuItem
                          class="task-menu-item"
                          onclick={() => onSetDueToday(task)}
                          disabled={task.repeatTemplate}
                        >
                          <CalendarCheck size={14} />
                          Set due today
                        </DropdownMenuItem>
                        <DropdownMenuSeparator />
                      {/if}
                      <DropdownMenuItem
                        class="task-menu-item"
                        onclick={() => onDefer(task, 1)}
                        disabled={task.repeatTemplate}
                      >
                        <CalendarClock size={14} />
                        Defer to tomorrow
                      </DropdownMenuItem>
                      <DropdownMenuItem
                        class="task-menu-item"
                        onclick={() => onDeferToWeekday(task, 5)}
                        disabled={task.repeatTemplate}
                      >
                        <CalendarClock size={14} />
                        Defer to Friday
                      </DropdownMenuItem>
                      <DropdownMenuItem
                        class="task-menu-item"
                        onclick={() => onDeferToWeekday(task, 6)}
                        disabled={task.repeatTemplate}
                      >
                        <CalendarClock size={14} />
                        Defer to weekend
                      </DropdownMenuItem>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem
                        class="task-menu-item"
                        onclick={() => onOpenDue(task)}
                        disabled={task.repeatTemplate}
                      >
                        <CalendarPlus size={14} />
                        Set due date…
                      </DropdownMenuItem>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem class="task-menu-item" onclick={() => onOpenTrash(task)}>
                        <Trash2 size={14} />
                        Delete
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </div>
              </li>
            {/each}
          </ul>
        </div>
      {/each}
    {/if}
  </div>
{/if}

<style>
  .things-list {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .things-content {
    max-width: 720px;
    width: 100%;
    margin: 0 auto;
    padding: 1.5rem 2rem 2rem;
    display: flex;
    flex-direction: column;
    gap: 1.25rem;
  }

  .things-section-title {
    font-size: 0.85rem;
    color: var(--color-muted-foreground);
    font-weight: 600;
    margin-bottom: 0.65rem;
  }

  .things-task {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
    padding: 0.6rem 0.75rem;
    border: 1px solid var(--color-border);
    border-radius: 0.75rem;
    background: var(--color-card);
    transition:
      opacity 160ms ease,
      transform 160ms ease;
  }

  .things-task.completing {
    opacity: 0.5;
    transform: translateY(-2px) scale(0.995);
  }

  .task-left {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    flex: 1;
    min-width: 0;
  }

  .task-right {
    display: flex;
    align-items: center;
    flex-shrink: 0;
    gap: 0.5rem;
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
    transition:
      border-color 160ms ease,
      color 160ms ease,
      background 160ms ease;
  }

  .check:hover {
    color: var(--color-foreground);
    border-color: var(--color-foreground);
  }

  .check.completing {
    background: var(--color-sidebar-accent);
    border-color: transparent;
    color: var(--color-foreground);
  }

  .repeat-badge {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 26px;
    height: 26px;
    border-radius: 999px;
    border: 1px solid var(--color-border);
    color: var(--color-muted-foreground);
    background: var(--color-secondary);
  }

  .repeat-icon {
    color: var(--color-muted-foreground);
  }

  .notes-icon {
    color: var(--color-muted-foreground);
    display: inline-flex;
    align-items: center;
    opacity: 0.75;
    position: relative;
  }

  .notes-tooltip {
    position: absolute;
    bottom: 140%;
    left: 50%;
    transform: translateX(-50%);
    background: var(--color-popover);
    color: var(--color-popover-foreground);
    border: 1px solid var(--color-border);
    border-radius: 0.5rem;
    padding: 0.5rem 0.65rem;
    font-size: 0.75rem;
    line-height: 1.2;
    width: max-content;
    max-width: 260px;
    white-space: pre-wrap;
    box-shadow: 0 10px 24px rgba(0, 0, 0, 0.25);
    opacity: 0;
    pointer-events: none;
    transition: opacity 120ms ease;
    z-index: 2;
  }

  .notes-icon:hover .notes-tooltip,
  .notes-icon:focus-within .notes-tooltip {
    opacity: 1;
  }

  .task-title {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.95rem;
    font-weight: 500;
  }

  .meta {
    font-size: 0.75rem;
    color: var(--color-muted-foreground);
    margin-top: 0.15rem;
    text-transform: uppercase;
  }

  .due-pill {
    font-size: 0.75rem;
    padding: 0.15rem 0.5rem;
    border-radius: 999px;
    border: 1px solid var(--color-border);
    color: var(--color-muted-foreground);
    background: var(--color-secondary);
  }

  .task-menu-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 30px;
    height: 30px;
    border-radius: 999px;
    border: 1px solid transparent;
    background: transparent;
    color: var(--color-muted-foreground);
    opacity: 0;
    pointer-events: none;
    transition:
      opacity 160ms ease,
      border-color 160ms ease,
      color 160ms ease,
      background 160ms ease;
  }

  .things-task:hover .task-menu-btn,
  .task-menu-btn:focus-visible {
    opacity: 1;
    pointer-events: auto;
  }

  .task-menu-btn:hover {
    color: var(--color-foreground);
    border-color: var(--color-border);
    background: var(--color-secondary);
  }

  :global(.task-menu) {
    min-width: 190px;
  }

  :global(.task-menu-item) {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .task-rename-input {
    width: 100%;
    border-radius: 0.5rem;
    border: 1px solid var(--color-border);
    background: transparent;
    padding: 0.2rem 0.45rem;
    color: var(--color-foreground);
    font-size: 0.95rem;
  }

  .new-task-card {
    border: 1px solid var(--color-border);
    border-radius: 0.9rem;
    background: var(--color-card);
    padding: 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .new-task-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-size: 0.9rem;
    font-weight: 600;
  }

  .new-task-target {
    font-size: 0.75rem;
    padding: 0.15rem 0.5rem;
    border-radius: 999px;
    border: 1px solid var(--color-border);
    color: var(--color-muted-foreground);
    background: var(--color-secondary);
  }

  .new-task-input,
  .new-task-notes,
  .new-task-date,
  .new-task-select {
    width: 100%;
    border-radius: 0.6rem;
    border: 1px solid var(--color-border);
    background: transparent;
    padding: 0.6rem 0.75rem;
    color: var(--color-foreground);
  }

  .new-task-select {
    appearance: none;
    -webkit-appearance: none;
    background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20' fill='none' stroke='%239aa0a6' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M6 8l4 4 4-4'/%3E%3C/svg%3E");
    background-repeat: no-repeat;
    background-position: right 1rem center;
    background-size: 0.9rem;
    padding-right: 2.5rem;
  }

  .new-task-notes {
    resize: vertical;
    min-height: 44px;
  }

  .new-task-meta {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 1rem;
  }

  .new-task-label {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    font-size: 0.75rem;
    color: var(--color-muted-foreground);
    text-transform: uppercase;
  }

  .new-task-actions {
    display: flex;
    justify-content: flex-end;
    gap: 0.5rem;
  }

  .new-task-btn {
    border-radius: 999px;
    border: 1px solid transparent;
    padding: 0.35rem 0.9rem;
    font-size: 0.8rem;
    cursor: pointer;
    transition:
      background 150ms ease,
      border-color 150ms ease,
      color 150ms ease;
  }

  .new-task-btn.primary {
    background: var(--color-primary);
    color: var(--color-primary-foreground);
  }

  .new-task-btn.secondary {
    background: var(--color-secondary);
    color: var(--color-secondary-foreground);
    border-color: var(--color-border);
  }

  .new-task-btn:disabled {
    opacity: 0.6;
    cursor: default;
  }

  .new-task-error {
    font-size: 0.8rem;
    color: var(--color-destructive);
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

  .things-loading-icon {
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
