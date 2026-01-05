<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { thingsStore, type ThingsNewTaskDraft } from '$lib/stores/things';
  import type { ThingsTask } from '$lib/types/things';
  import ThingsTasksTitlebar from '$lib/components/things/ThingsTasksTitlebar.svelte';
  import ThingsTasksContent from '$lib/components/things/ThingsTasksContent.svelte';
  import ThingsTaskDialogs from '$lib/components/things/ThingsTaskDialogs.svelte';
  import {
    dueLabel as formatDueLabel,
    formatDateKeyForDate,
    formatDateKeyForToday,
    formatDateKeyWithOffset,
    getTaskDueDate,
    nextWeekday,
    taskSubtitle as formatTaskSubtitle
  } from '$lib/components/things/tasksUtils';
  import {
    computeTasksViewState,
    isSameSelection
  } from '$lib/components/things/ThingsTasksViewState';

  let view = computeTasksViewState($thingsStore);
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
  $: {
    view = computeTasksViewState($thingsStore);
    newTaskDraft = view.newTaskDraft;
    draftSaving = $thingsStore.newTaskSaving;
    draftError = $thingsStore.newTaskError;
    showDraft = view.showDraft;
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
        draftTargetLabel = view.projectTitleById.get(newTaskDraft.projectId) ?? 'Project';
      } else if (newTaskDraft.areaId) {
        draftTargetLabel = view.areaTitleById.get(newTaskDraft.areaId) ?? 'Area';
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
    formatTaskSubtitle(
      task,
      view.selectionType,
      view.selectionLabel,
      view.projectTitleById,
      view.areaTitleById
    );
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
    const task = notesTask;
    if (!task) return;
    await runTaskUpdate(task.id, () => thingsStore.updateNotes(task.id, notesValue));
    closeNotesDialog();
  }

  function openMoveDialog(task: ThingsTask) {
    moveTask = task;
    moveListId = task.projectId ?? task.areaId ?? '';
    moveListName =
      (moveListId && (view.projectTitleById.get(moveListId) ?? view.areaTitleById.get(moveListId))) ??
      '';
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
    moveListName = view.projectTitleById.get(value) ?? view.areaTitleById.get(value) ?? '';
  }

  async function commitMove() {
    const task = moveTask;
    if (!task || !moveListId) return;
    await runTaskUpdate(task.id, () => thingsStore.moveTask(task.id, moveListId, moveListName));
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
    const task = trashTask;
    if (!task) return;
    await runTaskUpdate(task.id, () => thingsStore.trashTask(task.id));
    closeTrashDialog();
  }

  async function handleSetDueDate() {
    const task = dueTask;
    if (!task || !dueDateValue) return;
    await runTaskUpdate(task.id, () => thingsStore.setDueDate(task.id, dueDateValue, 'set_due'));
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
    const project = view.projectTitleById.get(value);
    const area = view.areaTitleById.get(value);
    draftTargetLabel = project ?? area ?? '';
    draftListName = project ?? area ?? '';
  }

  const refreshTasks = () => {
    thingsStore.load(view.selection, { force: true, silent: true });
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
    selectionLabel={view.selectionLabel}
    titleIcon={view.titleIcon}
    totalCount={view.totalCount}
    hasLoaded={view.hasLoaded}
  />

  <ThingsTasksContent
    tasks={view.tasks}
    sections={view.sections}
    selectionType={view.selectionType}
    selectionLabel={view.selectionLabel}
    selectionQuery={view.selectionQuery}
    isLoading={view.isLoading}
    searchPending={view.searchPending}
    error={view.error}
    {showDraft}
    bind:draftTitle
    bind:draftNotes
    bind:draftDueDate
    {draftSaving}
    {draftError}
    {draftTargetLabel}
    bind:draftListId
    bind:titleInput
    areaOptions={view.areaOptions}
    projectsByArea={view.projectsByArea}
    orphanProjects={view.orphanProjects}
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
    areaOptions={view.areaOptions}
    projectsByArea={view.projectsByArea}
    orphanProjects={view.orphanProjects}
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
