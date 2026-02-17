<script context="module" lang="ts">
	export type TaskViewType = 'inbox' | 'today' | 'upcoming' | 'group' | 'project' | 'search';
</script>

<script lang="ts">
	import type { Task, TaskGroup, TaskProject } from '$lib/types/tasks';
	import LoadingGlyph from '$lib/components/loading/LoadingGlyph.svelte';
	import { LOADING_SIZES } from '$lib/components/loading/loadingSizes';
	import TaskDraftForm from './TaskDraftForm.svelte';
	import TaskList from './TaskList.svelte';

	export let tasks: Task[] = [];
	export let sections: { id: string; title: string; tasks: Task[] }[] = [];
	export let selectionType: TaskViewType = 'today';
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
	export let groupOptions: TaskGroup[] = [];
	export let projectsByGroup: Map<string, TaskProject[]> = new Map();
	export let orphanProjects: TaskProject[] = [];

	export let busyTasks: Set<string> = new Set();
	export let editingTaskId: string | null = null;
	export let renameValue = '';
	export let renameInput: HTMLInputElement | null = null;

	export let onDraftInput: () => void;
	export let onCreateTask: () => void;
	export let onCancelDraft: () => void;
	export let onDraftListChange: (value: string) => void;

	export let onComplete: (taskId: string) => void;
	export let onStartRename: (task: Task) => void;
	export let onCommitRename: (task: Task) => void;
	export let onCancelRename: () => void;
	export let onOpenNotes: (task: Task) => void;
	export let onOpenMove: (task: Task) => void;
	export let onOpenDue: (task: Task) => void;
	export let onOpenRepeat: (task: Task) => void;
	export let onClearDue: (task: Task) => void;
	export let onOpenTrash: (task: Task) => void;
	export let onDefer: (task: Task, days: number) => void;
	export let onDeferToWeekday: (task: Task, targetDay: number) => void;
	export let onSetDueToday: (task: Task) => void;

	export let taskSubtitle: (task: Task) => string;
	export let dueLabel: (task: Task) => string | null;
</script>

{#if isLoading || (selectionType === 'search' && searchPending)}
	<div class="tasks-state">
		<LoadingGlyph size={LOADING_SIZES.page} />
		{#if selectionType === 'search'}
			Loading search results…
		{:else}
			Loading tasks…
		{/if}
	</div>
{:else if error}
	<div class="tasks-error">{error}</div>
{:else}
	<div class="tasks-content">
		{#if showDraft}
			<TaskDraftForm
				bind:draftTitle
				bind:draftNotes
				bind:draftDueDate
				bind:draftListId
				bind:titleInput
				{draftSaving}
				{draftError}
				{draftTargetLabel}
				{groupOptions}
				{projectsByGroup}
				{orphanProjects}
				{onDraftInput}
				{onCreateTask}
				{onCancelDraft}
				{onDraftListChange}
			/>
		{/if}
		{#if tasks.length === 0}
			<div class="tasks-state">
				<div class="tasks-empty-glyph">
					<LoadingGlyph
						size={LOADING_SIZES.hero}
						lightSrc="/images/loading-light-128.gif"
						darkSrc="/images/loading-dark-128.gif"
					/>
				</div>
				{#if selectionLabel === 'Today'}
					All done for the day
				{:else if selectionType === 'search'}
					No results for "{selectionQuery}"
				{:else}
					No tasks to show.
				{/if}
			</div>
		{:else}
			<TaskList
				{sections}
				{selectionType}
				{busyTasks}
				{editingTaskId}
				bind:renameValue
				bind:renameInput
				{onComplete}
				{onStartRename}
				{onCommitRename}
				{onCancelRename}
				{onOpenNotes}
				{onOpenMove}
				{onOpenDue}
				{onOpenRepeat}
				{onClearDue}
				{onOpenTrash}
				{onDefer}
				{onDeferToWeekday}
				{onSetDueToday}
				{taskSubtitle}
				{dueLabel}
			/>
		{/if}
	</div>
{/if}

<style>
	.tasks-content {
		max-width: 720px;
		width: 100%;
		margin: 0 auto;
		padding: 1.5rem 2rem 2rem;
		display: flex;
		flex-direction: column;
		gap: 1.25rem;
	}

	.tasks-state {
		display: flex;
		flex-direction: column;
		align-items: center;
		text-align: center;
		color: var(--color-muted-foreground);
		padding: 1.5rem 2rem;
		max-width: 720px;
		margin: 0 auto;
	}

	.tasks-empty-glyph {
		margin-bottom: 0.75rem;
	}

	.tasks-error {
		color: #d55b5b;
		padding: 1.5rem 2rem;
		max-width: 720px;
		margin: 0 auto;
	}
</style>
