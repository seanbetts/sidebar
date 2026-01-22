<script context="module" lang="ts">
	export type TaskViewType = 'inbox' | 'today' | 'upcoming' | 'area' | 'project' | 'search';
</script>

<script lang="ts">
	import type { Task } from '$lib/types/tasks';
	import {
		CalendarCheck,
		CalendarClock,
		CalendarPlus,
		Circle,
		FileText,
		Layers,
		MoreHorizontal,
		Pencil,
		Repeat,
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
	import { recurrenceLabel } from '$lib/components/tasks/tasksUtils';

	export let sections: { id: string; title: string; tasks: Task[] }[] = [];
	export let selectionType: TaskViewType = 'today';
	export let busyTasks: Set<string> = new Set();
	export let editingTaskId: string | null = null;
	export let renameValue = '';
	export let renameInput: HTMLInputElement | null = null;

	export let onComplete: (taskId: string) => void;
	export let onStartRename: (task: Task) => void;
	export let onCommitRename: (task: Task) => void;
	export let onCancelRename: () => void;
	export let onOpenNotes: (task: Task) => void;
	export let onOpenMove: (task: Task) => void;
	export let onOpenDue: (task: Task) => void;
	export let onOpenTrash: (task: Task) => void;
	export let onDefer: (task: Task, days: number) => void;
	export let onDeferToWeekday: (task: Task, targetDay: number) => void;
	export let onSetDueToday: (task: Task) => void;

	export let taskSubtitle: (task: Task) => string;
	export let dueLabel: (task: Task) => string | null;
</script>

{#each sections as section}
	<div class="tasks-section">
		{#if section.title}
			<div class="tasks-section-title">{section.title}</div>
		{/if}
		<ul class="tasks-list">
			{#each section.tasks as task}
				<li class="tasks-task" class:completing={busyTasks.has(task.id)}>
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
									{#if recurrenceLabel(task)}
										<span class="repeat-label">{recurrenceLabel(task)}</span>
									{/if}
									<Repeat size={14} class="repeat-icon" title="Repeating task" />
								{/if}
							</div>
							{#if taskSubtitle(task)}
								<div class="meta">{taskSubtitle(task)}</div>
							{/if}
						</div>
					</div>
					<div class="task-right">
						{#if selectionType === 'area' || selectionType === 'project' || selectionType === 'search'}
							<span class="due-pill" title={recurrenceLabel(task) ?? ''}>
								{dueLabel(task) ?? 'No Date'}
							</span>
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

<style>
	.tasks-list {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}

	.tasks-section-title {
		font-size: 0.85rem;
		color: var(--color-muted-foreground);
		font-weight: 600;
		margin-bottom: 0.65rem;
	}

	.tasks-task {
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

	.tasks-task.completing {
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

	:global(.repeat-icon) {
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
		top: 140%;
		left: 50%;
		transform: translateX(-50%);
		background: var(--color-popover);
		color: var(--color-popover-foreground);
		border: 1px solid var(--color-border);
		border-radius: 0.5rem;
		padding: 0.75rem 1rem;
		font-size: 0.875rem;
		line-height: 1.5;
		width: max-content;
		max-width: 360px;
		white-space: pre-wrap;
		word-break: break-word;
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

	.repeat-label {
		font-size: 0.7rem;
		letter-spacing: 0.02em;
		text-transform: uppercase;
		color: var(--color-muted-foreground);
		background: var(--color-secondary);
		border-radius: 999px;
		padding: 0.1rem 0.4rem;
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

	:global(.task-menu-btn) {
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

	:global(.tasks-task:hover .task-menu-btn),
	:global(.task-menu-btn:focus-visible) {
		opacity: 1;
		pointer-events: auto;
	}

	:global(.task-menu-btn:hover) {
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
</style>
