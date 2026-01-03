<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { thingsStore, type ThingsNewTaskDraft, type ThingsSelection } from '$lib/stores/things';
  import type { ThingsArea, ThingsProject, ThingsTask } from '$lib/types/things';
  import {
    Check,
    Circle,
    CalendarCheck,
    CalendarClock,
    CalendarPlus,
    Inbox,
    Layers,
    List,
    FileText,
    MoreHorizontal,
    Repeat,
    Search,
    Pencil,
    Trash2
  } from 'lucide-svelte';
  import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuSeparator,
    DropdownMenuTrigger
  } from '$lib/components/ui/dropdown-menu';
  import {
    AlertDialog,
    AlertDialogAction,
    AlertDialogCancel,
    AlertDialogContent,
    AlertDialogDescription,
    AlertDialogFooter,
    AlertDialogHeader,
    AlertDialogTitle
  } from '$lib/components/ui/alert-dialog';

  type TaskSection = {
    id: string;
    title: string;
    tasks: ThingsTask[];
  };

  let tasks: ThingsTask[] = [];
  let selectionLabel = 'Today';
  let titleIcon = CalendarCheck;
  let selectionQuery = '';
  let areas: ThingsArea[] = [];
  let projects: ThingsProject[] = [];
  let isLoading = false;
  let searchPending = false;
  let error = '';
  let sections: TaskSection[] = [];
  let totalCount = 0;
  let hasLoaded = false;
  let projectTitleById = new Map<string, string>();
  let areaTitleById = new Map<string, string>();
  let selectionType: ThingsTaskViewType = 'today';
  let selection: ThingsSelection = { type: 'today' };
  let busyTasks = new Set<string>();
  let refreshTimer: ReturnType<typeof setInterval> | null = null;
  let showDueDialog = false;
  let dueTask: ThingsTask | null = null;
  let dueDateValue = '';
  let editingTaskId: string | null = null;
  let renameValue = '';
  let showNotesDialog = false;
  let notesTask: ThingsTask | null = null;
  let notesValue = '';
  let showMoveDialog = false;
  let moveTask: ThingsTask | null = null;
  let moveListId = '';
  let moveListName = '';
  let showTrashDialog = false;
  let trashTask: ThingsTask | null = null;
  let renameInput: HTMLInputElement | null = null;
  let newTaskDraft: ThingsNewTaskDraft | null = null;
  let activeDraft: ThingsNewTaskDraft | null = null;
  let draftTitle = '';
  let draftNotes = '';
  let draftDueDate = '';
  let draftSaving = false;
  let draftError = '';
  let draftTargetLabel = '';
  let showDraft = false;
  let draftFocused = false;
  let draftListId = '';
  let draftListName = '';
  let titleInput: HTMLInputElement | null = null;
  let areaOptions: ThingsArea[] = [];
  let projectOptions: ThingsProject[] = [];
  let projectsByArea = new Map<string, ThingsProject[]>();
  let orphanProjects: ThingsProject[] = [];

  type ThingsTaskViewType = 'inbox' | 'today' | 'upcoming' | 'area' | 'project' | 'search';

  const MS_PER_DAY = 24 * 60 * 60 * 1000;

  $: {
    const state = $thingsStore;
    tasks = state.tasks;
    areas = state.areas;
    projects = state.projects;
    selection = state.selection;
    isLoading = state.isLoading;
    searchPending = state.searchPending;
    error = state.error;
    selectionType = state.selection.type;
    newTaskDraft = state.newTaskDraft;
    draftSaving = state.newTaskSaving;
    draftError = state.newTaskError;
    const projectIds = new Set(projects.map((project) => project.id));
    const filteredTasks = tasks.filter((task) => task.status !== 'project');
    const visibleTasks =
      selectionType === 'area' || selectionType === 'search'
        ? filteredTasks.filter((task) => !projectIds.has(task.id))
        : filteredTasks;
    const sortedTasks =
      selectionType === 'area' || selectionType === 'project' || selectionType === 'search'
        ? sortByDueDate(visibleTasks)
        : visibleTasks;
    projectTitleById = new Map(projects.map((project) => [project.id, project.title]));
    areaTitleById = new Map(areas.map((area) => [area.id, area.title]));
    areaOptions = [...areas].sort((a, b) => a.title.localeCompare(b.title));
    projectOptions = [...projects].sort((a, b) => a.title.localeCompare(b.title));
    projectsByArea = new Map();
    orphanProjects = [];
    projectOptions.forEach((project) => {
      if (project.areaId) {
        const bucket = projectsByArea.get(project.areaId) ?? [];
        bucket.push(project);
        projectsByArea.set(project.areaId, bucket);
      } else {
        orphanProjects.push(project);
      }
    });
    selectionQuery =
      selectionType === 'search' && 'query' in state.selection ? state.selection.query : '';
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
    } else if (selectionType === 'search') {
      selectionLabel = selectionQuery ? `Search: ${selectionQuery}` : 'Search';
      titleIcon = Search;
      sections = buildSearchSections(sortedTasks, areas);
    } else {
      selectionLabel = 'Tasks';
      sections = sortedTasks.length ? [{ id: 'all', title: '', tasks: sortedTasks }] : [];
    }
    totalCount = sections.reduce((sum, section) => sum + section.tasks.length, 0);
    hasLoaded = !isLoading;
    showDraft = Boolean(newTaskDraft && isSameSelection(selection, newTaskDraft.selection));
  }

  function isSameSelection(a: ThingsSelection, b: ThingsSelection) {
    if (a.type !== b.type) return false;
    if (a.type === 'area' || a.type === 'project') {
      return a.id === (b as { id: string }).id;
    }
    if (a.type === 'search') {
      return a.query === (b as { query: string }).query;
    }
    return true;
  }

  $: {
    if (newTaskDraft && newTaskDraft !== activeDraft) {
      activeDraft = newTaskDraft;
      draftTitle = newTaskDraft.title;
      draftNotes = newTaskDraft.notes;
      draftDueDate = newTaskDraft.dueDate;
      draftListId = newTaskDraft.listId ?? '';
      draftListName = newTaskDraft.listName ?? '';
      if (newTaskDraft.projectId) {
        draftTargetLabel = projectTitleById.get(newTaskDraft.projectId) ?? 'Project';
      } else if (newTaskDraft.areaId) {
        draftTargetLabel = areaTitleById.get(newTaskDraft.areaId) ?? 'Area';
      } else {
        draftTargetLabel = '';
      }
      draftFocused = false;
    } else if (!newTaskDraft && activeDraft) {
      activeDraft = null;
      draftTitle = '';
      draftNotes = '';
      draftDueDate = '';
      draftTargetLabel = '';
      draftListId = '';
      draftListName = '';
      draftFocused = false;
    }
  }

  $: if (showDraft && titleInput && !draftFocused) {
    titleInput.focus();
    draftFocused = true;
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

  function nextWeekday(date: Date, targetDay: number): Date {
    const currentDay = date.getDay();
    let daysAhead = (targetDay - currentDay + 7) % 7;
    if (daysAhead === 0) {
      daysAhead = 7;
    }
    return addDays(date, daysAhead);
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
    const buckets = new Map<string, { title: string; tasks: ThingsTask[] }>();

    areas.forEach((area) => {
      buckets.set(`area:${area.id}`, { title: area.title, tasks: [] });
    });

    tasks.forEach((task) => {
      const project = task.projectId ? projects.find((item) => item.id === task.projectId) : null;
      const areaId = task.areaId ?? project?.areaId ?? null;
      if (areaId) {
        const key = `area:${areaId}`;
        if (!buckets.has(key)) {
          const title = areaTitleById.get(areaId) ?? 'Area';
          buckets.set(key, { title, tasks: [] });
        }
        buckets.get(key)?.tasks.push(task);
        return;
      }
      if (task.projectId) {
        const key = `project:${task.projectId}`;
        if (!buckets.has(key)) {
          buckets.set(key, {
            title: projectTitleById.get(task.projectId) ?? 'Project',
            tasks: []
          });
        }
        buckets.get(key)?.tasks.push(task);
        return;
      }
      if (!buckets.has('other')) {
        buckets.set('other', { title: 'Other', tasks: [] });
      }
      buckets.get('other')?.tasks.push(task);
    });

    areas.forEach((area) => {
      const bucket = buckets.get(`area:${area.id}`);
      if (bucket?.tasks.length) {
        sections.push({ id: area.id, title: bucket.title, tasks: bucket.tasks });
      }
    });

    buckets.forEach((bucket, key) => {
      if (key.startsWith('project:') && bucket.tasks.length) {
        sections.push({ id: key, title: bucket.title, tasks: bucket.tasks });
      }
    });

    const other = buckets.get('other');
    if (other?.tasks.length) {
      sections.push({ id: 'other', title: other.title, tasks: other.tasks });
    }

    return sections;
  }

  function buildSearchSections(tasks: ThingsTask[], areas: ThingsArea[]): TaskSection[] {
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
        sections.push({ id: area.id, title: area.title, tasks: sortByDueDate(bucket) });
      }
    });
    if (unassigned.length) {
      sections.push({ id: 'other', title: 'Other', tasks: sortByDueDate(unassigned) });
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
    if (selectionType === 'search') {
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
    if (dayDiff === 0) {
      return 'Today';
    }
    if (dayDiff === 1) {
      return 'Tomorrow';
    }
    if (dayDiff > 1 && dayDiff <= 6) {
      return date.toLocaleDateString(undefined, { weekday: 'short' });
    }
    return date.toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
  }

  function openDueDialog(task: ThingsTask) {
    dueTask = task;
    dueDateValue = (taskDeadline(task) ?? formatDateKey(new Date())).slice(0, 10);
    showDueDialog = true;
  }

  function closeDueDialog() {
    showDueDialog = false;
    dueTask = null;
    dueDateValue = '';
  }

  function startRename(task: ThingsTask) {
    editingTaskId = task.id;
    renameValue = task.title;
  }

  function cancelRename() {
    editingTaskId = null;
    renameValue = '';
    renameInput?.blur();
  }

  async function commitRename(task: ThingsTask) {
    const nextTitle = renameValue.trim();
    if (!nextTitle || nextTitle === task.title) {
      cancelRename();
      return;
    }
    cancelRename();
    await runTaskUpdate(task.id, () => thingsStore.renameTask(task.id, nextTitle));
  }

  $: if (editingTaskId && renameInput) {
    renameInput.focus();
    renameInput.select();
  }

  function openNotesDialog(task: ThingsTask) {
    notesTask = task;
    notesValue = task.notes ?? '';
    showNotesDialog = true;
  }

  function closeNotesDialog() {
    showNotesDialog = false;
    notesTask = null;
    notesValue = '';
  }

  async function saveNotes() {
    if (!notesTask) return;
    await runTaskUpdate(notesTask.id, () => thingsStore.updateNotes(notesTask.id, notesValue));
    closeNotesDialog();
  }

  function openMoveDialog(task: ThingsTask) {
    moveTask = task;
    moveListId = task.projectId ?? task.areaId ?? '';
    moveListName =
      (moveListId && (projectTitleById.get(moveListId) ?? areaTitleById.get(moveListId))) ?? '';
    showMoveDialog = true;
  }

  function closeMoveDialog() {
    showMoveDialog = false;
    moveTask = null;
    moveListId = '';
    moveListName = '';
  }

  function handleMoveListChange(value: string) {
    moveListId = value;
    moveListName = projectTitleById.get(value) ?? areaTitleById.get(value) ?? '';
  }

  async function commitMove() {
    if (!moveTask || !moveListId) return;
    await runTaskUpdate(moveTask.id, () => thingsStore.moveTask(moveTask.id, moveListId, moveListName));
    closeMoveDialog();
  }

  function openTrashDialog(task: ThingsTask) {
    trashTask = task;
    showTrashDialog = true;
  }

  function closeTrashDialog() {
    trashTask = null;
    showTrashDialog = false;
  }

  async function confirmTrash() {
    if (!trashTask) return;
    await runTaskUpdate(trashTask.id, () => thingsStore.trashTask(trashTask.id));
    closeTrashDialog();
  }

  async function handleSetDueDate() {
    if (!dueTask || !dueDateValue) return;
    await runTaskUpdate(dueTask.id, () => thingsStore.setDueDate(dueTask.id, dueDateValue, 'set_due'));
    closeDueDialog();
  }

  async function handleDefer(task: ThingsTask, days: number) {
    const dateValue = formatDateKey(addDays(new Date(), days));
    await runTaskUpdate(task.id, () => thingsStore.setDueDate(task.id, dateValue, 'defer'));
  }

  async function handleDeferToWeekday(task: ThingsTask, targetDay: number) {
    const dateValue = formatDateKey(nextWeekday(new Date(), targetDay));
    await runTaskUpdate(task.id, () => thingsStore.setDueDate(task.id, dateValue, 'defer'));
  }

  async function handleSetDueToday(task: ThingsTask) {
    const dateValue = formatDateKey(new Date());
    await runTaskUpdate(task.id, () => thingsStore.setDueDate(task.id, dateValue, 'defer'));
  }

  async function runTaskUpdate(taskId: string, action: () => Promise<void>) {
    if (busyTasks.has(taskId)) return;
    busyTasks = new Set(busyTasks).add(taskId);
    await new Promise((resolve) => setTimeout(resolve, 180));
    try {
      await action();
    } finally {
      const next = new Set(busyTasks);
      next.delete(taskId);
      busyTasks = next;
    }
  }

  async function handleComplete(taskId: string) {
    await runTaskUpdate(taskId, () => thingsStore.completeTask(taskId));
  }

  function handleCancelDraft() {
    thingsStore.cancelNewTask();
  }

  async function handleCreateTask() {
    await thingsStore.createTask({
      title: draftTitle,
      notes: draftNotes,
      dueDate: draftDueDate,
      listId: draftListId || null,
      listName: draftListName || null
    });
  }

  function handleDraftListChange(value: string) {
    draftListId = value;
    thingsStore.clearNewTaskError();
    if (!value) {
      draftTargetLabel = '';
      draftListName = '';
      return;
    }
    const project = projectTitleById.get(value);
    const area = areaTitleById.get(value);
    draftTargetLabel = project ?? area ?? '';
    draftListName = project ?? area ?? '';
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
      {#if newTaskDraft && showDraft}
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
                handleCreateTask();
              }
            }}
            oninput={() => thingsStore.clearNewTaskError()}
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
                onchange={(event) => handleDraftListChange((event.currentTarget as HTMLSelectElement).value)}
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
            <button class="new-task-btn secondary" onclick={handleCancelDraft} disabled={draftSaving}>
              Cancel
            </button>
            <button
              class="new-task-btn primary"
              onclick={handleCreateTask}
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
                        onclick={() => handleComplete(task.id)}
                        aria-label="Complete task"
                        disabled={busyTasks.has(task.id)}
                      >
                        <Circle size={14} />
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
                              commitRename(task);
                            }
                            if (event.key === 'Escape') {
                              event.preventDefault();
                              cancelRename();
                            }
                          }}
                          onblur={() => commitRename(task)}
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
                        <DropdownMenuItem class="task-menu-item" onclick={() => startRename(task)}>
                          <Pencil size={14} />
                          Rename
                        </DropdownMenuItem>
                        <DropdownMenuItem class="task-menu-item" onclick={() => openNotesDialog(task)}>
                          <FileText size={14} />
                          Edit notes
                        </DropdownMenuItem>
                        <DropdownMenuItem class="task-menu-item" onclick={() => openMoveDialog(task)}>
                          <Layers size={14} />
                          Move to…
                        </DropdownMenuItem>
                        <DropdownMenuSeparator />
                        {#if selectionType !== 'today'}
                          <DropdownMenuItem
                            class="task-menu-item"
                            onclick={() => handleSetDueToday(task)}
                            disabled={task.repeatTemplate}
                          >
                            <CalendarCheck size={14} />
                            Set due today
                          </DropdownMenuItem>
                          <DropdownMenuSeparator />
                        {/if}
                        <DropdownMenuItem
                          class="task-menu-item"
                          onclick={() => handleDefer(task, 1)}
                          disabled={task.repeatTemplate}
                        >
                          <CalendarClock size={14} />
                          Defer to tomorrow
                        </DropdownMenuItem>
                        <DropdownMenuItem
                          class="task-menu-item"
                          onclick={() => handleDeferToWeekday(task, 5)}
                          disabled={task.repeatTemplate}
                        >
                          <CalendarClock size={14} />
                          Defer to Friday
                        </DropdownMenuItem>
                        <DropdownMenuItem
                          class="task-menu-item"
                          onclick={() => handleDeferToWeekday(task, 6)}
                          disabled={task.repeatTemplate}
                        >
                          <CalendarClock size={14} />
                          Defer to weekend
                        </DropdownMenuItem>
                        <DropdownMenuSeparator />
                      <DropdownMenuItem
                        class="task-menu-item"
                        onclick={() => openDueDialog(task)}
                        disabled={task.repeatTemplate}
                      >
                        <CalendarPlus size={14} />
                        Set due date…
                      </DropdownMenuItem>
                      <DropdownMenuSeparator />
                        <DropdownMenuItem class="task-menu-item" onclick={() => openTrashDialog(task)}>
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
</div>

<AlertDialog bind:open={showDueDialog}>
  <AlertDialogContent class="task-due-dialog">
    <AlertDialogHeader>
      <AlertDialogTitle>Set due date</AlertDialogTitle>
      <AlertDialogDescription>
        Choose a due date for {dueTask?.title ?? 'this task'}.
      </AlertDialogDescription>
    </AlertDialogHeader>
    <input class="task-date-input" type="date" bind:value={dueDateValue} />
    <AlertDialogFooter>
      <AlertDialogCancel onclick={closeDueDialog}>Cancel</AlertDialogCancel>
      <AlertDialogAction onclick={handleSetDueDate} disabled={!dueDateValue}>
        Save
      </AlertDialogAction>
    </AlertDialogFooter>
  </AlertDialogContent>
</AlertDialog>

<AlertDialog bind:open={showNotesDialog}>
  <AlertDialogContent class="task-notes-dialog">
    <AlertDialogHeader>
      <AlertDialogTitle>Edit notes</AlertDialogTitle>
      <AlertDialogDescription>
        Update notes for {notesTask?.title ?? 'this task'}.
      </AlertDialogDescription>
    </AlertDialogHeader>
    <textarea class="task-notes-input" rows="6" bind:value={notesValue}></textarea>
    <AlertDialogFooter>
      <AlertDialogCancel onclick={closeNotesDialog}>Cancel</AlertDialogCancel>
      <AlertDialogAction onclick={saveNotes}>Save</AlertDialogAction>
    </AlertDialogFooter>
  </AlertDialogContent>
</AlertDialog>

<AlertDialog bind:open={showMoveDialog}>
  <AlertDialogContent class="task-move-dialog">
    <AlertDialogHeader>
      <AlertDialogTitle>Move task</AlertDialogTitle>
      <AlertDialogDescription>
        Choose a new area or project for {moveTask?.title ?? 'this task'}.
      </AlertDialogDescription>
    </AlertDialogHeader>
    <select
      class="task-move-select"
      bind:value={moveListId}
      onchange={(event) => handleMoveListChange((event.currentTarget as HTMLSelectElement).value)}
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
    <AlertDialogFooter>
      <AlertDialogCancel onclick={closeMoveDialog}>Cancel</AlertDialogCancel>
      <AlertDialogAction onclick={commitMove} disabled={!moveListId}>
        Move
      </AlertDialogAction>
    </AlertDialogFooter>
  </AlertDialogContent>
</AlertDialog>

<AlertDialog bind:open={showTrashDialog}>
  <AlertDialogContent class="task-trash-dialog">
    <AlertDialogHeader>
      <AlertDialogTitle>Delete task</AlertDialogTitle>
      <AlertDialogDescription>
        Delete {trashTask?.title ?? 'this task'}? This will move it to the Things Trash.
      </AlertDialogDescription>
    </AlertDialogHeader>
    <AlertDialogFooter>
      <AlertDialogCancel onclick={closeTrashDialog}>Cancel</AlertDialogCancel>
      <AlertDialogAction onclick={confirmTrash}>Delete</AlertDialogAction>
    </AlertDialogFooter>
  </AlertDialogContent>
</AlertDialog>

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

  .task-due-dialog {
    max-width: 420px;
  }

  .task-date-input {
    width: 100%;
    margin-top: 0.75rem;
    border-radius: 0.5rem;
    border: 1px solid var(--color-border);
    background: transparent;
    padding: 0.5rem 0.75rem;
    color: var(--color-foreground);
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

  .task-notes-dialog,
  .task-move-dialog,
  .task-trash-dialog {
    max-width: 460px;
  }

  .task-notes-input {
    width: 100%;
    margin-top: 0.75rem;
    border-radius: 0.6rem;
    border: 1px solid var(--color-border);
    background: transparent;
    padding: 0.6rem 0.75rem;
    color: var(--color-foreground);
    resize: vertical;
  }

  .task-move-select {
    width: 100%;
    margin-top: 0.75rem;
    border-radius: 0.6rem;
    border: 1px solid var(--color-border);
    background: transparent;
    padding: 0.6rem 0.75rem;
    color: var(--color-foreground);
    appearance: none;
    -webkit-appearance: none;
    background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20' fill='none' stroke='%239aa0a6' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M6 8l4 4 4-4'/%3E%3C/svg%3E");
    background-repeat: no-repeat;
    background-position: right 1rem center;
    background-size: 0.9rem;
    padding-right: 2.5rem;
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
