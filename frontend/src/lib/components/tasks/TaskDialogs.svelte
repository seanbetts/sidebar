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

	export let showRepeatDialog = false;
	export let repeatTask: Task | null = null;
	export let repeatType = 'daily';
	export let repeatInterval = '1';
	export let repeatWeekday = '1';
	export let repeatMonthDay = '1';
	export let repeatStartDate = '';
	export let onCloseRepeat: () => void;
	export let onSaveRepeat: () => void;

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

<AlertDialog bind:open={showRepeatDialog}>
	<AlertDialogContent class="task-repeat-dialog">
		<AlertDialogHeader>
			<AlertDialogTitle>Repeat task</AlertDialogTitle>
			<AlertDialogDescription>
				Adjust how often {repeatTask?.title ?? 'this task'} repeats.
			</AlertDialogDescription>
		</AlertDialogHeader>
		<div class="task-repeat-fields">
			<label class="task-repeat-label" for="repeat-type">Repeat</label>
			<select id="repeat-type" class="task-repeat-select" bind:value={repeatType}>
				<option value="none">Does not repeat</option>
				<option value="daily">Daily</option>
				<option value="weekly">Weekly</option>
				<option value="monthly">Monthly</option>
			</select>

			{#if repeatType !== 'none'}
				<div class="task-repeat-row">
					<label class="task-repeat-label" for="repeat-interval">Every</label>
					<input
						id="repeat-interval"
						class="task-repeat-input"
						type="number"
						min="1"
						bind:value={repeatInterval}
					/>
					<span class="task-repeat-suffix">
						{repeatType === 'daily' ? 'days' : repeatType === 'weekly' ? 'weeks' : 'months'}
					</span>
				</div>
				{#if repeatType === 'weekly'}
					<div class="task-repeat-row">
						<label class="task-repeat-label" for="repeat-weekday">On</label>
						<select id="repeat-weekday" class="task-repeat-select" bind:value={repeatWeekday}>
							<option value="0">Sunday</option>
							<option value="1">Monday</option>
							<option value="2">Tuesday</option>
							<option value="3">Wednesday</option>
							<option value="4">Thursday</option>
							<option value="5">Friday</option>
							<option value="6">Saturday</option>
						</select>
					</div>
				{/if}
				{#if repeatType === 'monthly'}
					<div class="task-repeat-row">
						<label class="task-repeat-label" for="repeat-month-day">On day</label>
						<input
							id="repeat-month-day"
							class="task-repeat-input"
							type="number"
							min="1"
							max="31"
							bind:value={repeatMonthDay}
						/>
					</div>
				{/if}
				<div class="task-repeat-row">
					<label class="task-repeat-label" for="repeat-start">Start date</label>
					<input
						id="repeat-start"
						class="task-repeat-input task-repeat-input--date"
						type="date"
						bind:value={repeatStartDate}
					/>
				</div>
			{/if}
		</div>
		<AlertDialogFooter>
			<AlertDialogCancel onclick={onCloseRepeat}>Cancel</AlertDialogCancel>
			<AlertDialogAction onclick={onSaveRepeat}>Save</AlertDialogAction>
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

	:global(.task-repeat-dialog) {
		max-width: 460px;
	}

	.task-repeat-fields {
		display: grid;
		gap: 0.75rem;
		margin-top: 0.75rem;
	}

	.task-repeat-row {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		flex-wrap: wrap;
	}

	.task-repeat-label {
		min-width: 80px;
		font-size: 0.8rem;
		color: var(--color-muted-foreground);
	}

	.task-repeat-input,
	.task-repeat-select {
		border-radius: 0.5rem;
		border: 1px solid var(--color-border);
		background: transparent;
		padding: 0.45rem 0.7rem;
		color: var(--color-foreground);
	}

	.task-repeat-input {
		width: 120px;
	}

	.task-repeat-input--date {
		width: 180px;
	}

	:global(.dark) .task-date-input::-webkit-calendar-picker-indicator,
	:global(.dark) .task-repeat-input--date::-webkit-calendar-picker-indicator {
		filter: invert(1);
		opacity: 0.85;
	}

	.task-repeat-select {
		min-width: 180px;
	}

	.task-repeat-suffix {
		font-size: 0.8rem;
		color: var(--color-muted-foreground);
	}
</style>
