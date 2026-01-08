<script lang="ts">
	import {
		Table,
		TableBody,
		TableCell,
		TableHead,
		TableHeader,
		TableRow
	} from '$lib/components/ui/table';
	import { Pencil, Trash2 } from 'lucide-svelte';
	import type { Memory } from '$lib/types/memory';

	export let memories: Memory[] = [];
	export let draftById: Record<string, { name: string } | undefined> = {};
	export let displayName: (path: string) => string;
	export let onEdit: (memory: Memory) => void;
	export let onDelete: (memory: Memory) => void;
</script>

<div class="memory-table-wrapper">
	<Table>
		<colgroup>
			<col />
			<col style="width: 96px" />
			<col style="width: 64px" />
			<col style="width: 64px" />
		</colgroup>
		<TableHeader>
			<TableRow>
				<TableHead>Name</TableHead>
				<TableHead>Updated</TableHead>
				<TableHead>Edit</TableHead>
				<TableHead>Delete</TableHead>
			</TableRow>
		</TableHeader>
		<TableBody>
			{#each memories as memory (memory.id)}
				<TableRow>
					<TableCell>
						{draftById[memory.id]?.name ?? displayName(memory.path)}
					</TableCell>
					<TableCell>
						{new Date(memory.updated_at).toLocaleDateString()}
					</TableCell>
					<TableCell>
						<button
							class="settings-button ghost icon"
							on:click={() => onEdit(memory)}
							aria-label="Edit memory"
						>
							<Pencil size={14} />
						</button>
					</TableCell>
					<TableCell>
						<button
							class="settings-button ghost icon"
							on:click={() => onDelete(memory)}
							aria-label="Delete memory"
						>
							<Trash2 size={14} />
						</button>
					</TableCell>
				</TableRow>
			{/each}
		</TableBody>
	</Table>
</div>

<style>
	.memory-table-wrapper {
		border: 1px solid var(--color-border);
		border-radius: 0.9rem;
		overflow: hidden;
		background: var(--color-card);
	}

	.memory-table-wrapper :global([data-slot='table']) {
		table-layout: fixed;
	}

	.memory-table-wrapper :global([data-slot='table-row']) {
		height: 68px;
	}

	.memory-table-wrapper :global([data-slot='table-body'] [data-slot='table-cell']:first-child) {
		font-weight: 600;
		color: var(--color-foreground);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.memory-table-wrapper :global([data-slot='table-body'] [data-slot='table-cell']:nth-child(2)) {
		color: var(--color-muted-foreground);
		font-size: 0.78rem;
		white-space: nowrap;
	}

	.memory-table-wrapper :global([data-slot='table-cell']:nth-child(3)),
	.memory-table-wrapper :global([data-slot='table-cell']:nth-child(4)),
	.memory-table-wrapper :global([data-slot='table-head']:nth-child(3)),
	.memory-table-wrapper :global([data-slot='table-head']:nth-child(4)) {
		width: 64px;
		min-width: 64px;
		text-align: center;
		padding: 0.2rem 0.2rem !important;
	}

	.memory-table-wrapper :global([data-slot='table-cell']:nth-child(2)),
	.memory-table-wrapper :global([data-slot='table-head']:nth-child(2)) {
		width: 96px;
	}

	.memory-table-wrapper :global([data-slot='table-cell']:nth-child(3)),
	.memory-table-wrapper :global([data-slot='table-cell']:nth-child(4)) {
		vertical-align: middle;
	}

	.memory-table-wrapper :global([data-slot='table-cell']:nth-child(3) .settings-button),
	.memory-table-wrapper :global([data-slot='table-cell']:nth-child(4) .settings-button) {
		margin: 0 auto;
	}

	.memory-table-wrapper :global(.settings-button.icon) {
		padding: 0.2rem;
		width: 28px;
		height: 28px;
	}

	.memory-table-wrapper :global(.settings-button.ghost) {
		padding: 0.2rem;
	}

	@media (max-width: 720px) {
		.memory-table-wrapper :global([data-slot='table-head']:nth-child(2)),
		.memory-table-wrapper :global([data-slot='table-cell']:nth-child(2)) {
			display: none;
		}
	}
</style>
