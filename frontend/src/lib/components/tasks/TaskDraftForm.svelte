<script lang="ts">
	import type { TaskArea, TaskProject } from '$lib/types/tasks';

	export let draftTitle = '';
	export let draftNotes = '';
	export let draftDueDate = '';
	export let draftSaving = false;
	export let draftError = '';
	export let draftTargetLabel = '';
	export let draftListId = '';
	export let titleInput: HTMLInputElement | null = null;
	export let areaOptions: TaskArea[] = [];
	export let projectsByArea: Map<string, TaskProject[]> = new Map();
	export let orphanProjects: TaskProject[] = [];

	export let onDraftInput: () => void;
	export let onCreateTask: () => void;
	export let onCancelDraft: () => void;
	export let onDraftListChange: (value: string) => void;
</script>

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

<style>
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
</style>
