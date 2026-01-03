<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { thingsStore, type ThingsSelection } from '$lib/stores/things';
  import type { ThingsArea, ThingsProject, ThingsTask } from '$lib/types/things';
  import { Check, CalendarCheck, CalendarClock, Inbox, Layers, List, Repeat } from 'lucide-svelte';

  type TaskSection = {
    id: string;
    title: string;
    tasks: ThingsTask[];
  };

  let tasks: ThingsTask[] = [];
  let selectionLabel = 'Today';
  let titleIcon = CalendarCheck;
  let areas: ThingsArea[] = [];
  let projects: ThingsProject[] = [];
  let isLoading = false;
  let error = '';
  let sections: TaskSection[] = [];
  let totalCount = 0;
  let hasLoaded = false;
  let projectTitleById = new Map<string, string>();
  let areaTitleById = new Map<string, string>();
  let selectionType: ThingsTaskViewType = 'today';
  let selection: ThingsSelection = { type: 'today' };
  const completing = new Set<string>();
  let refreshTimer: ReturnType<typeof setInterval> | null = null;

  type ThingsTaskViewType = 'inbox' | 'today' | 'upcoming' | 'area' | 'project';

  const MS_PER_DAY = 24 * 60 * 60 * 1000;

  $: {
    const state = $thingsStore;
    tasks = state.tasks;
    areas = state.areas;
    projects = state.projects;
    selection = state.selection;
    isLoading = state.isLoading;
    error = state.error;
    selectionType = state.selection.type;
    const projectIds = new Set(projects.map((project) => project.id));
    const visibleTasks =
      selectionType === 'area'
        ? tasks.filter((task) => !projectIds.has(task.id) && task.status !== 'project')
        : tasks;
    const sortedTasks =
      selectionType === 'area' || selectionType === 'project'
        ? sortByDueDate(visibleTasks)
        : visibleTasks;
    projectTitleById = new Map(projects.map((project) => [project.id, project.title]));
    areaTitleById = new Map(areas.map((area) => [area.id, area.title]));
    if (selectionType === 'today') {
      selectionLabel = 'Today';
      titleIcon = CalendarCheck;
      sections = buildTodaySections(sortedTasks, areas);
    } else if (selectionType === 'upcoming') {
      selectionLabel = 'Upcoming';
      titleIcon = CalendarClock;
      sections = buildUpcomingSections(sortedTasks);
    } else if (selectionType === 'inbox') {
      selectionLabel = 'Inbox';
      titleIcon = Inbox;
      sections = sortedTasks.length ? [{ id: 'all', title: '', tasks: sortedTasks }] : [];
    } else if (selectionType === 'area') {
      selectionLabel = areas.find((area) => area.id === state.selection.id)?.title || 'Area';
      titleIcon = Layers;
      sections = sortedTasks.length ? [{ id: 'all', title: '', tasks: sortedTasks }] : [];
    } else if (selectionType === 'project') {
      selectionLabel = projects.find((project) => project.id === state.selection.id)?.title || 'Project';
      titleIcon = List;
      sections = sortedTasks.length ? [{ id: 'all', title: '', tasks: sortedTasks }] : [];
    } else {
      selectionLabel = 'Tasks';
      sections = sortedTasks.length ? [{ id: 'all', title: '', tasks: sortedTasks }] : [];
    }
    totalCount = sections.reduce((sum, section) => sum + section.tasks.length, 0);
    hasLoaded = !isLoading;
  }

  function startOfDay(date: Date) {
    const next = new Date(date);
    next.setHours(0, 0, 0, 0);
    return next;
  }

  function formatDateKey(date: Date): string {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  function formatDayLabel(date: Date, dayDiff: number): string {
    if (dayDiff === 0) return 'Today';
    if (dayDiff === 1) return 'Tomorrow';
    return date.toLocaleDateString(undefined, { weekday: 'long', month: 'short', day: 'numeric' });
  }

  function formatWeekLabel(date: Date): string {
    const label = date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
    return `Week of ${label}`;
  }

  function formatMonthLabel(date: Date): string {
    return date.toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
  }

  function addDays(date: Date, days: number): Date {
    const next = new Date(date);
    next.setDate(next.getDate() + days);
    return next;
  }

  function taskDeadline(task: ThingsTask): string | null {
    return task.deadline ?? task.deadlineStart ?? null;
  }

  function parseTaskDate(task: ThingsTask): Date | null {
    const deadline = taskDeadline(task);
    if (!deadline) return null;
    return new Date(`${deadline.slice(0, 10)}T00:00:00`);
  }

  function buildTodaySections(tasks: ThingsTask[], areas: ThingsArea[]): TaskSection[] {
    const sections: TaskSection[] = [];
    const tasksByArea = new Map<string, ThingsTask[]>();
    const unassigned: ThingsTask[] = [];

    areas.forEach((area) => tasksByArea.set(area.id, []));
    tasks.forEach((task) => {
      if (task.areaId && tasksByArea.has(task.areaId)) {
        tasksByArea.get(task.areaId)?.push(task);
      } else {
        unassigned.push(task);
      }
    });

    areas.forEach((area) => {
      const bucket = tasksByArea.get(area.id) ?? [];
      if (bucket.length) {
        sections.push({ id: area.id, title: area.title, tasks: bucket });
      }
    });

    if (unassigned.length) {
      sections.push({ id: 'other', title: 'Other', tasks: unassigned });
    }

    return sections;
  }

  function buildUpcomingSections(tasks: ThingsTask[]): TaskSection[] {
    const today = startOfDay(new Date());
    const overdue: ThingsTask[] = [];
    const undated: ThingsTask[] = [];
    const daily = new Map<string, TaskSection>();
    const weekly = new Map<number, TaskSection>();
    const monthly = new Map<string, { date: Date; section: TaskSection }>();

    const sorted = [...tasks].sort((a, b) => {
      const dateA = parseTaskDate(a);
      const dateB = parseTaskDate(b);
      if (!dateA && !dateB) return 0;
      if (!dateA) return 1;
      if (!dateB) return -1;
      return dateA.getTime() - dateB.getTime();
    });

    sorted.forEach((task) => {
      const date = parseTaskDate(task);
      if (!date) {
        undated.push(task);
        return;
      }
      const dayDiff = Math.floor((startOfDay(date).getTime() - today.getTime()) / MS_PER_DAY);
      if (dayDiff < 0) {
        overdue.push(task);
        return;
      }
      if (dayDiff <= 6) {
        const key = formatDateKey(date);
        const label = formatDayLabel(date, dayDiff);
        const section = daily.get(key) ?? { id: key, title: label, tasks: [] };
        section.tasks.push(task);
        daily.set(key, section);
        return;
      }
      if (dayDiff <= 27) {
        const weekIndex = Math.floor(dayDiff / 7);
        const weekStart = addDays(today, weekIndex * 7);
        const label = formatWeekLabel(weekStart);
        const section = weekly.get(weekIndex) ?? { id: `week-${weekIndex}`, title: label, tasks: [] };
        section.tasks.push(task);
        weekly.set(weekIndex, section);
        return;
      }
      const monthKey = `${date.getFullYear()}-${date.getMonth()}`;
      const existing = monthly.get(monthKey);
      if (existing) {
        existing.section.tasks.push(task);
      } else {
        monthly.set(monthKey, {
          date,
          section: { id: `month-${monthKey}`, title: formatMonthLabel(date), tasks: [task] }
        });
      }
    });

    const sections: TaskSection[] = [];
    if (overdue.length) {
      sections.push({ id: 'overdue', title: 'Overdue', tasks: overdue });
    }
    for (let i = 0; i <= 6; i += 1) {
      const date = addDays(today, i);
      const key = formatDateKey(date);
      const section = daily.get(key);
      if (section) sections.push(section);
    }
    for (let weekIndex = 1; weekIndex <= 3; weekIndex += 1) {
      const section = weekly.get(weekIndex);
      if (section) sections.push(section);
    }
    const monthSections = [...monthly.values()].sort((a, b) => a.date.getTime() - b.date.getTime());
    monthSections.forEach((entry) => sections.push(entry.section));
    if (undated.length) {
      sections.push({ id: 'undated', title: 'No date', tasks: undated });
    }
    return sections;
  }

  function sortByDueDate(tasks: ThingsTask[]): ThingsTask[] {
    return [...tasks].sort((a, b) => {
      const dateA = parseTaskDate(a);
      const dateB = parseTaskDate(b);
      if (!dateA && !dateB) return 0;
      if (!dateA) return 1;
      if (!dateB) return -1;
      return dateA.getTime() - dateB.getTime();
    });
  }

  function taskSubtitle(task: ThingsTask): string {
    const projectTitle = task.projectId ? projectTitleById.get(task.projectId) : '';
    const areaTitle = task.areaId ? areaTitleById.get(task.areaId) : '';
    if (selectionType === 'project') {
      return projectTitle || selectionLabel;
    }
    if (selectionType === 'area') {
      return projectTitle || areaTitle || '';
    }
    if (selectionType === 'today' || selectionType === 'upcoming') {
      return projectTitle || areaTitle || '';
    }
    if (taskDeadline(task)) {
      return `Due ${taskDeadline(task)?.slice(0, 10)}`;
    }
    return projectTitle || areaTitle || '';
  }

  function dueLabel(task: ThingsTask): string | null {
    const date = parseTaskDate(task);
    if (!date) return null;
    const today = startOfDay(new Date());
    const dayDiff = Math.floor((startOfDay(date).getTime() - today.getTime()) / MS_PER_DAY);
    if (dayDiff >= 0 && dayDiff <= 6) {
      return date.toLocaleDateString(undefined, { weekday: 'short' });
    }
    return date.toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
  }

  async function handleComplete(taskId: string) {
    if (completing.has(taskId)) return;
    completing.add(taskId);
    await new Promise((resolve) => setTimeout(resolve, 180));
    try {
      await thingsStore.completeTask(taskId);
    } finally {
      completing.delete(taskId);
    }
  }

  const refreshTasks = () => {
    thingsStore.load(selection, { force: true, silent: true });
  };

  const handleVisibilityChange = () => {
    if (document.visibilityState === 'visible') {
      refreshTasks();
    }
  };

  onMount(() => {
    refreshTimer = setInterval(refreshTasks, 60000);
    window.addEventListener('focus', refreshTasks);
    document.addEventListener('visibilitychange', handleVisibilityChange);
  });

  onDestroy(() => {
    if (refreshTimer) {
      clearInterval(refreshTimer);
    }
    window.removeEventListener('focus', refreshTasks);
    document.removeEventListener('visibilitychange', handleVisibilityChange);
  });
</script>

<div class="things-view">
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

  {#if isLoading}
    <div class="things-state">Loading tasks…</div>
  {:else if error}
    <div class="things-error">{error}</div>
  {:else if tasks.length === 0}
    <div class="things-state">
      <img class="things-empty-logo" src="/images/logo.svg" alt="sideBar" />
      {#if selectionLabel === 'Today'}
        All done for the day
      {:else}
        No tasks to show.
      {/if}
    </div>
  {:else}
    <div class="things-content">
      {#each sections as section}
        <div class="things-section">
          {#if section.title}
            <div class="things-section-title">{section.title}</div>
          {/if}
          <ul class="things-list">
            {#each section.tasks as task}
              <li class="things-task" class:completing={completing.has(task.id)}>
                <div class="task-left">
                  {#if task.repeatTemplate}
                    <span class="repeat-badge" aria-label="Repeating task">
                      <Repeat size={14} />
                    </span>
                  {:else}
                    <button
                      class="check"
                      class:completing={completing.has(task.id)}
                      onclick={() => handleComplete(task.id)}
                      aria-label="Complete task"
                      disabled={completing.has(task.id)}
                    >
                      <Check size={14} />
                    </button>
                  {/if}
                  <div class="content">
                    <div class="task-title">
                      <span>{task.title}</span>
                      {#if task.repeating && !task.repeatTemplate}
                        <Repeat size={14} class="repeat-icon" />
                      {/if}
                    </div>
                    {#if taskSubtitle(task)}
                      <div class="meta">{taskSubtitle(task)}</div>
                    {/if}
                  </div>
                </div>
                {#if selectionType === 'area' || selectionType === 'project'}
                  <div class="task-right">
                    <span class="due-pill">{dueLabel(task) ?? 'No Date'}</span>
                  </div>
                {/if}
              </li>
            {/each}
          </ul>
        </div>
      {/each}
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

  .things-error {
    color: #d55b5b;
    padding: 1.5rem 2rem;
    max-width: 720px;
    margin: 0 auto;
  }
</style>
