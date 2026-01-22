<script lang="ts">
	import type { Task, TaskArea, TaskProject } from '$lib/types/tasks';
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

	export let showDueDialog = false;
	export let dueTask: Task | null = null;
	export let dueDateValue = '';
	export let onCloseDue: () => void;
	export let onSaveDue: () => void;

	export let showNotesDialog = false;
	export let notesTask: Task | null = null;
	export let notesValue = '';
	export let onCloseNotes: () => void;
	export let onSaveNotes: () => void;

	export let showMoveDialog = false;
	export let moveTask: Task | null = null;
	export let moveListId = '';
	export let areaOptions: TaskArea[] = [];
	export let projectsByArea: Map<string, TaskProject[]> = new Map();
	export let orphanProjects: TaskProject[] = [];
	export let onCloseMove: () => void;
	export let onMoveListChange: (value: string) => void;
	export let onCommitMove: () => void;

	export let showTrashDialog = false;
	export let trashTask: Task | null = null;
	export let onCloseTrash: () => void;
	export let onConfirmTrash: () => void;
</script>

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
			<AlertDialogCancel onclick={onCloseDue}>Cancel</AlertDialogCancel>
			<AlertDialogAction onclick={onSaveDue} disabled={!dueDateValue}>Save</AlertDialogAction>
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
			<AlertDialogCancel onclick={onCloseNotes}>Cancel</AlertDialogCancel>
			<AlertDialogAction onclick={onSaveNotes}>Save</AlertDialogAction>
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
			onchange={(event) => onMoveListChange((event.currentTarget as HTMLSelectElement).value)}
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
			<AlertDialogCancel onclick={onCloseMove}>Cancel</AlertDialogCancel>
			<AlertDialogAction onclick={onCommitMove} disabled={!moveListId}>Move</AlertDialogAction>
		</AlertDialogFooter>
	</AlertDialogContent>
</AlertDialog>

<AlertDialog bind:open={showTrashDialog}>
	<AlertDialogContent class="task-trash-dialog">
		<AlertDialogHeader>
			<AlertDialogTitle>Delete task</AlertDialogTitle>
			<AlertDialogDescription>
				Delete {trashTask?.title ?? 'this task'}? This will move it to the task trash.
			</AlertDialogDescription>
		</AlertDialogHeader>
		<AlertDialogFooter>
			<AlertDialogCancel onclick={onCloseTrash}>Cancel</AlertDialogCancel>
			<AlertDialogAction onclick={onConfirmTrash}>Delete</AlertDialogAction>
		</AlertDialogFooter>
	</AlertDialogContent>
</AlertDialog>

<style>
	:global(.task-due-dialog) {
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

	:global(.task-notes-dialog),
	:global(.task-move-dialog),
	:global(.task-trash-dialog) {
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
</style>
