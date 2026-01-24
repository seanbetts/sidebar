<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import { tasksStore, type TaskNewTaskDraft } from '$lib/stores/tasks';
	import type { Task } from '$lib/types/tasks';
	import TasksTitlebar from '$lib/components/tasks/TasksTitlebar.svelte';
	import TasksContent from '$lib/components/tasks/TasksContent.svelte';
	import TaskDialogs from '$lib/components/tasks/TaskDialogs.svelte';
	import {
		dueLabel as formatDueLabel,
		formatDateKeyForDate,
		formatDateKeyForToday,
		formatDateKeyWithOffset,
		getTaskDueDate,
		nextWeekday,
		taskSubtitle as formatTaskSubtitle
	} from '$lib/components/tasks/tasksUtils';
	import { computeTasksViewState } from '$lib/components/tasks/TasksViewState';

	let view = computeTasksViewState($tasksStore);
	let busyTasks = new Set<string>();
	let refreshTimer: ReturnType<typeof setInterval> | null = null;
	let showDueDialog = false;
	let dueTask: Task | null = null;
	let dueDateValue = '';
	let editingTaskId: string | null = null;
	let renameValue = '';
	let showNotesDialog = false;
	let notesTask: Task | null = null;
	let notesValue = '';
	let showMoveDialog = false;
	let moveTask: Task | null = null;
	let moveListId = '';
	let moveListName = '';
	let showRepeatDialog = false;
	let repeatTask: Task | null = null;
	let repeatType: 'none' | 'daily' | 'weekly' | 'monthly' = 'daily';
	let repeatInterval = '1';
	let repeatWeekday = '1';
	let repeatMonthDay = '1';
	let repeatStartDate = '';
	let showTrashDialog = false;
	let trashTask: Task | null = null;
	let renameInput: HTMLInputElement | null = null;
	let newTaskDraft: TaskNewTaskDraft | null = null;
	let activeDraft: TaskNewTaskDraft | null = null;
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
	let conflictNotice = '';
	$: {
		view = computeTasksViewState($tasksStore);
		newTaskDraft = view.newTaskDraft;
		draftSaving = $tasksStore.newTaskSaving;
		draftError = $tasksStore.newTaskError;
		showDraft = view.showDraft;
		conflictNotice = $tasksStore.conflictNotice;
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
			} else if (newTaskDraft.groupId) {
				draftTargetLabel = view.groupTitleById.get(newTaskDraft.groupId) ?? 'Group';
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

	const taskSubtitle = (task: Task) =>
		formatTaskSubtitle(
			task,
			view.selectionType,
			view.selectionLabel,
			view.projectTitleById,
			view.groupTitleById
		);
	const dueLabel = (task: Task) => formatDueLabel(task);

	function openDueDialog(task: Task) {
		dueTask = task;
		dueDateValue = (getTaskDueDate(task) ?? formatDateKeyForToday()).slice(0, 10);
		showDueDialog = true;
	}

	function closeDueDialog() {
		showDueDialog = false;
		dueTask = null;
		dueDateValue = '';
	}

	function startRename(task: Task) {
		editingTaskId = task.id;
		renameValue = task.title;
	}

	function cancelRename() {
		editingTaskId = null;
		renameValue = '';
		renameInput?.blur();
	}

	async function commitRename(task: Task) {
		const nextTitle = renameValue.trim();
		if (!nextTitle || nextTitle === task.title) {
			cancelRename();
			return;
		}
		cancelRename();
		await runTaskUpdate(task.id, () => tasksStore.renameTask(task.id, nextTitle));
	}

	$: if (editingTaskId && renameInput) {
		renameInput.focus();
		renameInput.select();
	}

	$: if (repeatType === 'weekly' && repeatStartDate) {
		repeatWeekday = String(toDate(repeatStartDate).getDay());
	}

	$: if (repeatType === 'monthly' && repeatStartDate) {
		repeatMonthDay = String(toDate(repeatStartDate).getDate());
	}

	function openNotesDialog(task: Task) {
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
		await runTaskUpdate(task.id, () => tasksStore.updateNotes(task.id, notesValue));
		closeNotesDialog();
	}

	function openMoveDialog(task: Task) {
		moveTask = task;
		moveListId = task.projectId ?? task.groupId ?? '';
		moveListName =
			(moveListId &&
				(view.projectTitleById.get(moveListId) ?? view.groupTitleById.get(moveListId))) ??
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
		moveListName = view.projectTitleById.get(value) ?? view.groupTitleById.get(value) ?? '';
	}

	async function commitMove() {
		const task = moveTask;
		if (!task || !moveListId) return;
		await runTaskUpdate(task.id, () => tasksStore.moveTask(task.id, moveListId, moveListName));
		closeMoveDialog();
	}

	function openRepeatDialog(task: Task) {
		repeatTask = task;
		const rule = task.recurrenceRule;
		if (rule?.type === 'daily' || rule?.type === 'weekly' || rule?.type === 'monthly') {
			repeatType = rule.type;
			repeatInterval = String(rule.interval ?? 1);
			repeatWeekday = String(rule.weekday ?? new Date().getDay());
			repeatMonthDay = String(rule.day_of_month ?? new Date().getDate());
		} else {
			repeatType = 'daily';
			repeatInterval = '1';
			repeatWeekday = String(new Date().getDay());
			repeatMonthDay = String(new Date().getDate());
		}
		repeatStartDate = (getTaskDueDate(task) ?? formatDateKeyForToday()).slice(0, 10);
		showRepeatDialog = true;
	}

	function closeRepeatDialog() {
		showRepeatDialog = false;
		repeatTask = null;
		repeatStartDate = '';
	}

	const toDate = (value: string) => new Date(`${value}T00:00:00`);
	const toDateKey = (value: Date) => formatDateKeyForDate(value);
	const clampDay = (value: number) => Math.min(31, Math.max(1, value));

	const nextOrSameWeekday = (date: Date, targetDay: number) => {
		const current = date.getDay();
		const delta = (targetDay - current + 7) % 7;
		const next = new Date(date);
		next.setDate(next.getDate() + delta);
		return next;
	};

	const nextMonthDay = (date: Date, day: number) => {
		const year = date.getFullYear();
		const month = date.getMonth();
		const daysInMonth = new Date(year, month + 1, 0).getDate();
		if (day <= daysInMonth) {
			return new Date(year, month, day);
		}
		const nextMonthDays = new Date(year, month + 2, 0).getDate();
		return new Date(year, month + 1, Math.min(day, nextMonthDays));
	};

	function handleRepeatWeekdayChange(value: string) {
		repeatWeekday = value;
		const day = Number.parseInt(value, 10);
		if (Number.isNaN(day)) return;
		const base = repeatStartDate ? toDate(repeatStartDate) : new Date();
		repeatStartDate = toDateKey(nextOrSameWeekday(base, day));
	}

	function handleRepeatMonthDayChange(value: string) {
		repeatMonthDay = value;
		const day = clampDay(Number.parseInt(value, 10));
		if (Number.isNaN(day)) return;
		const base = repeatStartDate ? toDate(repeatStartDate) : new Date();
		const nextDate = nextMonthDay(base, day);
		repeatStartDate = toDateKey(nextDate);
		repeatMonthDay = String(nextDate.getDate());
	}

	function handleRepeatStartDateChange(value: string) {
		repeatStartDate = value;
		const date = value ? toDate(value) : new Date();
		if (repeatType === 'weekly') {
			repeatWeekday = String(date.getDay());
		}
		if (repeatType === 'monthly') {
			repeatMonthDay = String(date.getDate());
		}
	}

	async function saveRepeat() {
		const task = repeatTask;
		if (!task) return;
		if (repeatType === 'none') {
			await runTaskUpdate(task.id, () => tasksStore.setRepeat(task.id, null, null));
			closeRepeatDialog();
			return;
		}
		const interval = Math.max(1, Number.parseInt(repeatInterval, 10) || 1);
		const rule = { type: repeatType, interval } as Task['recurrenceRule'];
		const startDate = repeatStartDate || formatDateKeyForToday();
		if (repeatType === 'weekly') {
			const date = toDate(startDate);
			rule.weekday = date.getDay();
			repeatWeekday = String(rule.weekday);
		}
		if (repeatType === 'monthly') {
			const date = toDate(startDate);
			rule.day_of_month = date.getDate();
			repeatMonthDay = String(rule.day_of_month);
		}
		await runTaskUpdate(task.id, () => tasksStore.setRepeat(task.id, rule, startDate));
		closeRepeatDialog();
	}

	function openTrashDialog(task: Task) {
		trashTask = task;
		showTrashDialog = true;
	}

	async function handleClearDue(task: Task) {
		await runTaskUpdate(task.id, () => tasksStore.clearDueDate(task.id));
	}

	function closeTrashDialog() {
		trashTask = null;
		showTrashDialog = false;
	}

	async function confirmTrash() {
		const task = trashTask;
		if (!task) return;
		closeTrashDialog();
		await runTaskUpdate(task.id, () => tasksStore.trashTask(task.id));
	}

	async function handleSetDueDate() {
		const task = dueTask;
		if (!task || !dueDateValue) return;
		await runTaskUpdate(task.id, () => tasksStore.setDueDate(task.id, dueDateValue, 'set_due'));
		closeDueDialog();
	}

	async function handleDefer(task: Task, days: number) {
		const dateValue = formatDateKeyWithOffset(days);
		await runTaskUpdate(task.id, () => tasksStore.setDueDate(task.id, dateValue, 'defer'));
	}

	async function handleDeferToWeekday(task: Task, targetDay: number) {
		const dateValue = formatDateKeyForDate(nextWeekday(new Date(), targetDay));
		await runTaskUpdate(task.id, () => tasksStore.setDueDate(task.id, dateValue, 'defer'));
	}

	async function handleSetDueToday(task: Task) {
		const dateValue = formatDateKeyForToday();
		await runTaskUpdate(task.id, () => tasksStore.setDueDate(task.id, dateValue, 'defer'));
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
		await runTaskUpdate(taskId, () => tasksStore.completeTask(taskId));
	}

	function handleCancelDraft() {
		tasksStore.cancelNewTask();
	}

	async function handleCreateTask() {
		await tasksStore.createTask({
			title: draftTitle,
			notes: draftNotes,
			dueDate: draftDueDate,
			listId: draftListId || null,
			listName: draftListName || null
		});
	}

	function handleDraftListChange(value: string) {
		draftListId = value;
		tasksStore.clearNewTaskError();
		if (!value) {
			draftTargetLabel = '';
			draftListName = '';
			return;
		}
		const project = view.projectTitleById.get(value);
		const group = view.groupTitleById.get(value);
		draftTargetLabel = project ?? group ?? '';
		draftListName = project ?? group ?? '';
	}

	const refreshTasks = () => {
		if (typeof navigator !== 'undefined' && !navigator.onLine) {
			return;
		}
		if (view.selectionType === 'search' && !view.selectionQuery) {
			return;
		}
		tasksStore.load(view.selection, { force: true, silent: true });
	};

	const handleRefreshConflicts = () => {
		tasksStore.clearConflictNotice();
		refreshTasks();
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

<div class="tasks-view">
	<TasksTitlebar
		selectionLabel={view.selectionLabel}
		titleIcon={view.titleIcon}
		totalCount={view.totalCount}
		hasLoaded={view.hasLoaded}
	/>
	<div class="tasks-scroll">
		{#if conflictNotice}
			<div class="tasks-conflict-banner">
				<span>{conflictNotice}</span>
				<button class="tasks-conflict-action" onclick={handleRefreshConflicts}>
					Refresh tasks
				</button>
			</div>
		{/if}

		<TasksContent
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
			groupOptions={view.groupOptions}
			projectsByGroup={view.projectsByGroup}
			orphanProjects={view.orphanProjects}
			{busyTasks}
			{editingTaskId}
			bind:renameValue
			bind:renameInput
			onDraftInput={() => tasksStore.clearNewTaskError()}
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
			onOpenRepeat={openRepeatDialog}
			onClearDue={handleClearDue}
			onOpenTrash={openTrashDialog}
			onDefer={handleDefer}
			onDeferToWeekday={handleDeferToWeekday}
			onSetDueToday={handleSetDueToday}
			{taskSubtitle}
			{dueLabel}
		/>
	</div>

	<TaskDialogs
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
		groupOptions={view.groupOptions}
		projectsByGroup={view.projectsByGroup}
		orphanProjects={view.orphanProjects}
		onCloseMove={closeMoveDialog}
		onMoveListChange={handleMoveListChange}
		onCommitMove={commitMove}
		bind:showRepeatDialog
		{repeatTask}
		bind:repeatType
		bind:repeatInterval
		bind:repeatWeekday
		bind:repeatMonthDay
		bind:repeatStartDate
		onRepeatWeekdayChange={handleRepeatWeekdayChange}
		onRepeatMonthDayChange={handleRepeatMonthDayChange}
		onRepeatStartDateChange={handleRepeatStartDateChange}
		onCloseRepeat={closeRepeatDialog}
		onSaveRepeat={saveRepeat}
		bind:showTrashDialog
		{trashTask}
		onCloseTrash={closeTrashDialog}
		onConfirmTrash={confirmTrash}
	/>
</div>

<style>
	.tasks-view {
		display: flex;
		flex-direction: column;
		height: 100%;
		padding: 0;
		gap: 1rem;
		overflow: hidden;
		box-sizing: border-box;
		padding-bottom: 1rem;
	}

	.tasks-scroll {
		flex: 1;
		min-height: 0;
		overflow-y: auto;
		padding-bottom: 0;
	}

	.tasks-conflict-banner {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
		padding: 0.6rem 0.75rem;
		border: 1px solid var(--color-border);
		border-radius: 0.75rem;
		background: var(--color-secondary);
		font-size: 0.8rem;
		color: var(--color-foreground);
	}

	.tasks-conflict-action {
		border-radius: 999px;
		border: 1px solid var(--color-border);
		padding: 0.25rem 0.7rem;
		background: var(--color-card);
		color: var(--color-foreground);
		font-size: 0.75rem;
		font-weight: 600;
		cursor: pointer;
	}

	.tasks-conflict-action:hover {
		border-color: var(--color-foreground);
	}
</style>
