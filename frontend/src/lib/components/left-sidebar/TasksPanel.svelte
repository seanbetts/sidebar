<script lang="ts">
	import { onMount } from 'svelte';
	import { tasksStore, type TaskSelection } from '$lib/stores/tasks';
	import { CalendarCheck, CalendarClock, Check, Layers, List } from 'lucide-svelte';

	let selection: TaskSelection = { type: 'today' };
	let tasksCount = 0;
	let counts: Record<string, number> = {};
	let areas: Array<{ id: string; title: string }> = [];
	let projects: Array<{ id: string; title: string; areaId?: string | null }> = [];
	let syncNotice = '';
	$: ({ selection, areas, projects, counts, syncNotice } = $tasksStore);
	$: tasksCount = $tasksStore.todayCount;
	$: sortedAreas = [...areas].sort((a, b) => a.title.localeCompare(b.title));
	$: sortedProjects = [...projects].sort((a, b) => a.title.localeCompare(b.title));
	$: projectsByArea = sortedAreas.map((area) => ({
		area,
		projects: sortedProjects.filter((project) => project.areaId === area.id)
	}));
	$: orphanProjects = sortedProjects.filter((project) => !project.areaId);

	function select(selection: TaskSelection) {
		tasksStore.load(selection);
	}

	onMount(() => {
		tasksStore.loadCounts();
	});
</script>

<div class="tasks-sections">
	<button
		class="tasks-item"
		class:active={selection.type === 'today'}
		onclick={() => select({ type: 'today' })}
	>
		<span class="row-label">
			<CalendarCheck size={14} />
			Today
		</span>
		<span class="meta">
			{#if tasksCount === 0}
				<Check size={12} />
			{:else}
				{tasksCount}
			{/if}
		</span>
	</button>
	<button
		class="tasks-item"
		class:active={selection.type === 'upcoming'}
		onclick={() => select({ type: 'upcoming' })}
	>
		<span class="row-label">
			<CalendarClock size={14} />
			Upcoming
		</span>
		<span class="meta">
			{#if (counts['upcoming'] ?? 0) === 0}
				<Check size={12} />
			{:else}
				{counts['upcoming'] ?? 0}
			{/if}
		</span>
	</button>
	<div class="tasks-divider"></div>
	{#if projectsByArea.length === 0}
		<div class="tasks-empty">No areas</div>
	{:else}
		{#each projectsByArea as group}
			<button
				class="tasks-item area-item"
				class:active={selection.type === 'area' && selection.id === group.area.id}
				onclick={() => select({ type: 'area', id: group.area.id })}
			>
				<span class="row-label">
					<Layers size={14} />
					{group.area.title}
				</span>
				<span class="meta">
					{#if (counts[`area:${group.area.id}`] ?? 0) === 0}
						<Check size={12} />
					{:else}
						{counts[`area:${group.area.id}`] ?? 0}
					{/if}
				</span>
			</button>
			{#each group.projects as project}
				<button
					class="tasks-item project-item"
					class:active={selection.type === 'project' && selection.id === project.id}
					onclick={() => select({ type: 'project', id: project.id })}
				>
					<span class="row-label">
						<List size={14} />
						{project.title}
					</span>
					<span class="meta">
						{#if (counts[`project:${project.id}`] ?? 0) === 0}
							<Check size={12} />
						{:else}
							{counts[`project:${project.id}`] ?? 0}
						{/if}
					</span>
				</button>
			{/each}
		{/each}
	{/if}
	{#if orphanProjects.length > 0}
		<div class="tasks-section-label">Projects</div>
		{#each orphanProjects as project}
			<button
				class="tasks-item project-item"
				class:active={selection.type === 'project' && selection.id === project.id}
				onclick={() => select({ type: 'project', id: project.id })}
			>
				<span class="row-label">
					<List size={14} />
					{project.title}
				</span>
				<span class="meta">
					{#if (counts[`project:${project.id}`] ?? 0) === 0}
						<Check size={12} />
					{:else}
						{counts[`project:${project.id}`] ?? 0}
					{/if}
				</span>
			</button>
		{/each}
	{/if}
	{#if syncNotice}
		<div class="tasks-footer">
			<div class="tasks-sync-notice">{syncNotice}</div>
		</div>
	{/if}
</div>

<style>
	.tasks-sections {
		display: flex;
		flex-direction: column;
		flex: 1;
		min-height: 0;
		overflow-y: auto;
		gap: 0.35rem;
		padding: 0.75rem 0.5rem 0.5rem;
	}

	.tasks-item {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.5rem;
		padding: 0.4rem 0.5rem;
		border-radius: 0.5rem;
		border: 1px solid transparent;
		background: transparent;
		color: var(--color-sidebar-foreground);
		cursor: pointer;
		font-size: 0.85rem;
	}

	.tasks-item:hover {
		background: var(--color-sidebar-accent);
	}

	.tasks-item.active {
		background: var(--color-sidebar-accent);
		border-color: var(--color-sidebar-border);
	}

	.row-label {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
	}

	.area-item {
		font-weight: 600;
	}

	.project-item {
		padding-left: 1.6rem;
	}

	.tasks-section-label {
		font-size: 0.7rem;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--color-muted-foreground);
		margin-top: 0.4rem;
	}

	.tasks-divider {
		height: 1px;
		background: var(--color-sidebar-border);
		margin: 0.5rem 0.25rem 0.35rem;
	}

	.tasks-empty {
		font-size: 0.8rem;
		color: var(--color-muted-foreground);
		padding-left: 0.5rem;
	}

	.tasks-footer {
		margin-top: auto;
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}

	.tasks-sync-notice {
		padding: 0.4rem 0.5rem 0.2rem;
		font-size: 0.72rem;
		color: var(--color-muted-foreground);
	}

	.meta {
		font-size: 0.75rem;
		color: var(--color-muted-foreground);
	}
</style>
