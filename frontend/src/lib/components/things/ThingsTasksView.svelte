<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { thingsStore, type ThingsNewTaskDraft, type ThingsSelection } from '$lib/stores/things';
  import type { ThingsArea, ThingsProject, ThingsTask } from '$lib/types/things';
  import { CalendarCheck, CalendarClock, Inbox, Layers, List, Search } from 'lucide-svelte';
  import ThingsTasksTitlebar from '$lib/components/things/ThingsTasksTitlebar.svelte';
  import ThingsTasksContent from '$lib/components/things/ThingsTasksContent.svelte';
  import ThingsTaskDialogs from '$lib/components/things/ThingsTaskDialogs.svelte';
  import {
    buildSearchSections,
    buildTodaySections,
    buildUpcomingSections,
    dueLabel as formatDueLabel,
    formatDateKeyForDate,
    formatDateKeyForToday,
    formatDateKeyWithOffset,
    getTaskDueDate,
    nextWeekday,
    sortByDueDate,
    taskSubtitle as formatTaskSubtitle,
    type TaskSection
  } from '$lib/components/things/tasksUtils';

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
      sections = buildTodaySections(sortedTasks, areas, projects, areaTitleById, projectTitleById);
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

  const taskSubtitle = (task: ThingsTask) =>
    formatTaskSubtitle(task, selectionType, selectionLabel, projectTitleById, areaTitleById);
  const dueLabel = (task: ThingsTask) => formatDueLabel(task);

  function openDueDialog(task: ThingsTask) {
    dueTask = task;
    dueDateValue = (getTaskDueDate(task) ?? formatDateKeyForToday()).slice(0, 10);
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
    const dateValue = formatDateKeyWithOffset(days);
    await runTaskUpdate(task.id, () => thingsStore.setDueDate(task.id, dateValue, 'defer'));
  }

  async function handleDeferToWeekday(task: ThingsTask, targetDay: number) {
    const dateValue = formatDateKeyForDate(nextWeekday(new Date(), targetDay));
    await runTaskUpdate(task.id, () => thingsStore.setDueDate(task.id, dateValue, 'defer'));
  }

  async function handleSetDueToday(task: ThingsTask) {
    const dateValue = formatDateKeyForToday();
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
  <ThingsTasksTitlebar
    {selectionLabel}
    {titleIcon}
    {totalCount}
    {hasLoaded}
  />

  <ThingsTasksContent
    {tasks}
    {sections}
    {selectionType}
    {selectionLabel}
    {selectionQuery}
    {isLoading}
    {searchPending}
    {error}
    {showDraft}
    bind:draftTitle
    bind:draftNotes
    bind:draftDueDate
    {draftSaving}
    {draftError}
    {draftTargetLabel}
    bind:draftListId
    bind:titleInput
    {areaOptions}
    {projectsByArea}
    {orphanProjects}
    {busyTasks}
    {editingTaskId}
    bind:renameValue
    bind:renameInput
    onDraftInput={() => thingsStore.clearNewTaskError()}
    onCreateTask={handleCreateTask}
    onCancelDraft={handleCancelDraft}
    onDraftListChange={handleDraftListChange}
    onComplete={handleComplete}
    onStartRename={startRename}
    onCommitRename={commitRename}
    onCancelRename={cancelRename}
    onOpenNotes={openNotesDialog}
    onOpenMove={openMoveDialog}
    onOpenDue={openDueDialog}
    onOpenTrash={openTrashDialog}
    onDefer={handleDefer}
    onDeferToWeekday={handleDeferToWeekday}
    onSetDueToday={handleSetDueToday}
    {taskSubtitle}
    {dueLabel}
  />

  <ThingsTaskDialogs
    bind:showDueDialog
    {dueTask}
    bind:dueDateValue
    onCloseDue={closeDueDialog}
    onSaveDue={handleSetDueDate}
    bind:showNotesDialog
    {notesTask}
    bind:notesValue
    onCloseNotes={closeNotesDialog}
    onSaveNotes={saveNotes}
    bind:showMoveDialog
    {moveTask}
    bind:moveListId
    {areaOptions}
    {projectsByArea}
    {orphanProjects}
    onCloseMove={closeMoveDialog}
    onMoveListChange={handleMoveListChange}
    onCommitMove={commitMove}
    bind:showTrashDialog
    {trashTask}
    onCloseTrash={closeTrashDialog}
    onConfirmTrash={confirmTrash}
  />
</div>

<style>
  .things-view {
    display: flex;
    flex-direction: column;
    height: 100%;
    padding: 0;
    gap: 1rem;
  }

</style>
