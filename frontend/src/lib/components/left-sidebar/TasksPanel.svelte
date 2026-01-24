<script lang="ts">
	import { onMount } from 'svelte';
	import { tasksStore, type TaskSelection } from '$lib/stores/tasks';
	import {
		CalendarCheck,
		CalendarClock,
		Check,
		Layers,
		List,
		MoreHorizontal,
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
	import ConfirmDialog from '$lib/components/left-sidebar/dialogs/ConfirmDialog.svelte';
	import TextInputDialog from '$lib/components/left-sidebar/dialogs/TextInputDialog.svelte';

	let selection: TaskSelection = { type: 'today' };
	let tasksCount = 0;
	let counts: Record<string, number> = {};
	let groups: Array<{ id: string; title: string }> = [];
	let projects: Array<{ id: string; title: string; groupId?: string | null }> = [];
	let syncNotice = '';
	let isRenameOpen = false;
	let isRenameBusy = false;
	let renameValue = '';
	let renameTarget: { type: 'group' | 'project'; id: string; title: string } | null = null;
	let isDeleteOpen = false;
	let isDeleteBusy = false;
	let deleteTarget: { type: 'group' | 'project'; id: string; title: string } | null = null;
	$: ({ selection, groups, projects, counts, syncNotice } = $tasksStore);
	$: tasksCount = $tasksStore.todayCount;
	$: sortedGroups = [...groups].sort((a, b) => a.title.localeCompare(b.title));
	$: sortedProjects = [...projects].sort((a, b) => a.title.localeCompare(b.title));
	$: projectsByGroup = sortedGroups.map((group) => ({
		group,
		projects: sortedProjects.filter((project) => project.groupId === group.id)
	}));
	$: orphanProjects = sortedProjects.filter((project) => !project.groupId);

	function select(selection: TaskSelection) {
		tasksStore.load(selection);
	}

	function openRename(target: { type: 'group' | 'project'; id: string; title: string }) {
		renameTarget = target;
		renameValue = target.title;
		isRenameOpen = true;
	}

	async function confirmRename() {
		if (!renameTarget || isRenameBusy) return;
		isRenameBusy = true;
		try {
			if (renameTarget.type === 'group') {
				await tasksStore.renameGroup(renameTarget.id, renameValue);
			} else {
				await tasksStore.renameProject(renameTarget.id, renameValue);
			}
			isRenameOpen = false;
			renameTarget = null;
			renameValue = '';
		} catch {
			// Errors handled by tasks store.
		} finally {
			isRenameBusy = false;
		}
	}

	function openDelete(target: { type: 'group' | 'project'; id: string; title: string }) {
		deleteTarget = target;
		isDeleteOpen = true;
	}

	async function confirmDelete() {
		if (!deleteTarget || isDeleteBusy) return;
		isDeleteBusy = true;
		try {
			if (deleteTarget.type === 'group') {
				await tasksStore.deleteGroup(deleteTarget.id);
			} else {
				await tasksStore.deleteProject(deleteTarget.id);
			}
			isDeleteOpen = false;
			deleteTarget = null;
		} catch {
			// Errors handled by tasks store.
		} finally {
			isDeleteBusy = false;
		}
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
	{#if projectsByGroup.length === 0}
		<div class="tasks-empty">No groups</div>
	{:else}
		{#each projectsByGroup as groupEntry}
			<div
				class="tasks-row"
				class:active={selection.type === 'group' && selection.id === groupEntry.group.id}
			>
				<button
					class="tasks-item tasks-item--label group-item"
					class:active={selection.type === 'group' && selection.id === groupEntry.group.id}
					onclick={() => select({ type: 'group', id: groupEntry.group.id })}
				>
					<span class="row-label">
						<Layers size={14} />
						{groupEntry.group.title}
					</span>
				</button>
				<div class="tasks-menu-wrap" onclick={(event) => event.stopPropagation()}>
					<DropdownMenu>
						<DropdownMenuTrigger class="tasks-menu" aria-label="Group actions">
							<MoreHorizontal size={16} />
						</DropdownMenuTrigger>
						<DropdownMenuContent align="end" sideOffset={6}>
							<DropdownMenuItem
								onclick={() =>
									openRename({
										type: 'group',
										id: groupEntry.group.id,
										title: groupEntry.group.title
									})}
							>
								<Pencil size={14} />
								Rename
							</DropdownMenuItem>
							<DropdownMenuSeparator />
							<DropdownMenuItem
								class="text-destructive"
								onclick={() =>
									openDelete({
										type: 'group',
										id: groupEntry.group.id,
										title: groupEntry.group.title
									})}
							>
								<Trash2 size={14} />
								Delete
							</DropdownMenuItem>
						</DropdownMenuContent>
					</DropdownMenu>
				</div>
				<span
					class="meta tasks-meta"
					role="button"
					tabindex="-1"
					onclick={() => select({ type: 'group', id: groupEntry.group.id })}
				>
					{#if (counts[`group:${groupEntry.group.id}`] ?? 0) === 0}
						<Check size={12} />
					{:else}
						{counts[`group:${groupEntry.group.id}`] ?? 0}
					{/if}
				</span>
			</div>
			{#each groupEntry.projects as project}
				<div
					class="tasks-row"
					class:active={selection.type === 'project' && selection.id === project.id}
				>
					<button
						class="tasks-item tasks-item--label project-item"
						class:active={selection.type === 'project' && selection.id === project.id}
						onclick={() => select({ type: 'project', id: project.id })}
					>
						<span class="row-label">
							<List size={14} />
							{project.title}
						</span>
					</button>
					<div class="tasks-menu-wrap" onclick={(event) => event.stopPropagation()}>
						<DropdownMenu>
							<DropdownMenuTrigger class="tasks-menu" aria-label="Project actions">
								<MoreHorizontal size={16} />
							</DropdownMenuTrigger>
							<DropdownMenuContent align="end" sideOffset={6}>
								<DropdownMenuItem
									onclick={() =>
										openRename({ type: 'project', id: project.id, title: project.title })}
								>
									<Pencil size={14} />
									Rename
								</DropdownMenuItem>
								<DropdownMenuSeparator />
								<DropdownMenuItem
									class="text-destructive"
									onclick={() =>
										openDelete({ type: 'project', id: project.id, title: project.title })}
								>
									<Trash2 size={14} />
									Delete
								</DropdownMenuItem>
							</DropdownMenuContent>
						</DropdownMenu>
					</div>
					<span
						class="meta tasks-meta"
						role="button"
						tabindex="-1"
						onclick={() => select({ type: 'project', id: project.id })}
					>
						{#if (counts[`project:${project.id}`] ?? 0) === 0}
							<Check size={12} />
						{:else}
							{counts[`project:${project.id}`] ?? 0}
						{/if}
					</span>
				</div>
			{/each}
		{/each}
	{/if}
	{#if orphanProjects.length > 0}
		<div class="tasks-section-label">Projects</div>
		{#each orphanProjects as project}
			<div
				class="tasks-row"
				class:active={selection.type === 'project' && selection.id === project.id}
			>
				<button
					class="tasks-item tasks-item--label project-item"
					class:active={selection.type === 'project' && selection.id === project.id}
					onclick={() => select({ type: 'project', id: project.id })}
				>
					<span class="row-label">
						<List size={14} />
						{project.title}
					</span>
				</button>
				<div class="tasks-menu-wrap" onclick={(event) => event.stopPropagation()}>
					<DropdownMenu>
						<DropdownMenuTrigger class="tasks-menu" aria-label="Project actions">
							<MoreHorizontal size={16} />
						</DropdownMenuTrigger>
						<DropdownMenuContent align="end" sideOffset={6}>
							<DropdownMenuItem
								onclick={() =>
									openRename({ type: 'project', id: project.id, title: project.title })}
							>
								<Pencil size={14} />
								Rename
							</DropdownMenuItem>
							<DropdownMenuSeparator />
							<DropdownMenuItem
								class="text-destructive"
								onclick={() =>
									openDelete({ type: 'project', id: project.id, title: project.title })}
							>
								<Trash2 size={14} />
								Delete
							</DropdownMenuItem>
						</DropdownMenuContent>
					</DropdownMenu>
				</div>
				<span
					class="meta tasks-meta"
					role="button"
					tabindex="-1"
					onclick={() => select({ type: 'project', id: project.id })}
				>
					{#if (counts[`project:${project.id}`] ?? 0) === 0}
						<Check size={12} />
					{:else}
						{counts[`project:${project.id}`] ?? 0}
					{/if}
				</span>
			</div>
		{/each}
	{/if}
	{#if syncNotice}
		<div class="tasks-footer">
			<div class="tasks-sync-notice">{syncNotice}</div>
		</div>
	{/if}
</div>
<TextInputDialog
	bind:open={isRenameOpen}
	title={`Rename ${renameTarget?.type ?? 'item'}`}
	placeholder={renameTarget?.type === 'group' ? 'Group name' : 'Project name'}
	confirmLabel="Rename"
	bind:value={renameValue}
	isBusy={isRenameBusy}
	onConfirm={confirmRename}
	onCancel={() => {
		isRenameOpen = false;
		renameTarget = null;
		renameValue = '';
	}}
/>
<ConfirmDialog
	bind:open={isDeleteOpen}
	title={`Delete ${deleteTarget?.type ?? 'item'}`}
	description={deleteTarget?.type === 'group'
		? 'This will delete the group and all nested projects and tasks.'
		: 'This will delete the project and all of its tasks.'}
	confirmLabel={isDeleteBusy ? 'Deleting...' : 'Delete'}
	onConfirm={confirmDelete}
	onCancel={() => {
		isDeleteOpen = false;
		deleteTarget = null;
	}}
/>

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

	.tasks-item--label {
		justify-content: flex-start;
	}

	.row-label {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
	}

	.tasks-row {
		display: flex;
		align-items: center;
		gap: 0.3rem;
		border-radius: 0.5rem;
		border: 1px solid transparent;
		padding-right: 0.5rem;
		cursor: pointer;
	}

	.tasks-row .tasks-item {
		flex: 1;
		min-width: 0;
		border: none;
		background: transparent;
	}

	.tasks-row:hover {
		background: var(--color-sidebar-accent);
	}

	.tasks-row.active {
		background: var(--color-sidebar-accent);
		border-color: var(--color-sidebar-border);
	}

	.tasks-menu-wrap {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		opacity: 0;
		visibility: hidden;
		pointer-events: none;
		transition: opacity 0.15s ease;
		cursor: pointer;
	}

	.tasks-menu {
		border: none;
		background: transparent;
		color: var(--color-muted-foreground);
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 1.75rem;
		height: 1.75rem;
		border-radius: 0.5rem;
		cursor: pointer;
	}

	.tasks-row:hover .tasks-menu-wrap,
	.tasks-row:focus-within .tasks-menu-wrap {
		opacity: 1;
		visibility: visible;
		pointer-events: auto;
	}

	.tasks-menu:hover {
		background: var(--color-sidebar-accent);
		color: var(--color-sidebar-foreground);
	}

	.tasks-meta {
		min-width: 1.5rem;
		text-align: right;
		cursor: pointer;
	}

	.group-item {
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
		display: inline-flex;
		align-items: center;
		justify-content: flex-end;
		font-size: 0.75rem;
		color: var(--color-muted-foreground);
		min-width: 1.5rem;
	}
</style>
