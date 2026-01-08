<script lang="ts">
	import {
		GripVertical,
		MoreHorizontal,
		Pencil,
		Pin,
		PinOff,
		Download,
		Trash2
	} from 'lucide-svelte';
	import type { ComponentType } from 'svelte';
	import type { IngestionListItem } from '$lib/types/ingestion';

	export let item: IngestionListItem;
	export let icon: ComponentType;
	export let menuKey = '';
	export let openMenuKey: string | null = null;
	export let displayName = '';
	export let dragOver = false;

	export let onOpen: (item: IngestionListItem) => void;
	export let onToggleMenu: (event: MouseEvent, menuKey: string) => void;
	export let onRename: (item: IngestionListItem) => void;
	export let onPinToggle: (item: IngestionListItem) => void;
	export let onDownload: (item: IngestionListItem) => void;
	export let onDelete: (item: IngestionListItem, event?: MouseEvent) => void;

	export let onDragStart: (event: DragEvent, id: string) => void;
	export let onDragOver: (event: DragEvent, id: string) => void;
	export let onDrop: (event: DragEvent, id: string) => void;
	export let onDragEnd: () => void;
</script>

<div
	class="ingested-row"
	class:drag-over={dragOver}
	data-ingested-menu-root={menuKey}
	role="listitem"
	aria-label={`Pinned file ${displayName}`}
	ondragover={(event) => onDragOver(event, item.file.id)}
	ondrop={(event) => onDrop(event, item.file.id)}
>
	<button class="ingested-item ingested-item--file" onclick={() => onOpen(item)}>
		<span class="ingested-icon">
			<svelte:component this={icon} size={16} />
		</span>
		<span class="ingested-name">{displayName}</span>
	</button>
	<button
		class="grab-handle"
		draggable="true"
		ondragstart={(event) => onDragStart(event, item.file.id)}
		ondragend={onDragEnd}
		onclick={(event) => event.stopPropagation()}
		aria-label="Reorder pinned file"
	>
		<GripVertical size={14} />
	</button>
	<button
		class="ingested-menu"
		onclick={(event) => onToggleMenu(event, menuKey)}
		aria-label="File actions"
	>
		<MoreHorizontal size={16} />
	</button>
	{#if openMenuKey === menuKey}
		<div class="ingested-menu-dropdown">
			<button class="menu-item" onclick={() => onRename(item)}>
				<Pencil size={16} />
				<span>Rename</span>
			</button>
			<button class="menu-item" onclick={() => onPinToggle(item)}>
				{#if item.file.pinned}
					<PinOff size={16} />
					<span>Unpin</span>
				{:else}
					<Pin size={16} />
					<span>Pin</span>
				{/if}
			</button>
			<button class="menu-item" onclick={() => onDownload(item)}>
				<Download size={16} />
				<span>Download</span>
			</button>
			<button class="menu-item" onclick={(event) => onDelete(item, event)}>
				<Trash2 size={16} />
				<span>Delete</span>
			</button>
		</div>
	{/if}
</div>

<style>
	.ingested-row {
		position: relative;
		display: flex;
		align-items: center;
		gap: 0.25rem;
		width: 100%;
	}

	.ingested-row.drag-over {
		background: none;
	}

	.ingested-row.drag-over::before {
		content: '';
		position: absolute;
		left: 0.5rem;
		right: 0.5rem;
		top: 0;
		height: 2px;
		border-radius: 999px;
		background: var(--color-sidebar-border);
	}

	.ingested-item {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.5rem;
		padding: 0.35rem 0.5rem;
		border: none;
		background: transparent;
		cursor: pointer;
		color: var(--color-foreground);
		text-align: left;
		min-width: 0;
		flex: 1;
	}

	.ingested-item:hover {
		background-color: var(--color-sidebar-accent);
	}

	.ingested-item--file {
		justify-content: flex-start;
		font-size: 0.85rem;
		min-width: 0;
		overflow: hidden;
	}

	.ingested-name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		flex: 1;
		min-width: 0;
		max-width: 100%;
	}

	.ingested-icon {
		display: flex;
		align-items: center;
		color: var(--color-muted-foreground);
	}

	.grab-handle {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		padding: 0.25rem;
		border: none;
		background: none;
		color: var(--color-muted-foreground);
		cursor: grab;
		border-radius: 0.375rem;
		opacity: 0;
		pointer-events: none;
		transition: opacity 0.2s ease;
	}

	.grab-handle:active {
		cursor: grabbing;
	}

	.ingested-row:hover .grab-handle {
		opacity: 0.9;
		pointer-events: auto;
	}

	.ingested-menu {
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 0.25rem;
		background: none;
		border: none;
		cursor: pointer;
		border-radius: 0.25rem;
		color: var(--color-muted-foreground);
		opacity: 0;
		align-self: center;
		transition: all 0.2s;
	}

	.ingested-row:hover .ingested-menu {
		opacity: 1;
	}

	.ingested-menu:hover {
		background-color: var(--color-accent);
	}

	.ingested-menu-dropdown {
		position: absolute;
		top: 100%;
		right: 0;
		margin-top: 0.25rem;
		background-color: var(--color-popover);
		border: 1px solid var(--color-border);
		border-radius: 0.375rem;
		box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
		z-index: 9999;
		min-width: 150px;
	}

	.ingested-menu-dropdown .menu-item {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		width: 100%;
		padding: 0.5rem 0.75rem;
		background: none;
		border: none;
		cursor: pointer;
		font-size: 0.85rem;
		text-align: left;
		transition: background-color 0.2s;
		color: var(--color-popover-foreground);
	}

	.ingested-menu-dropdown .menu-item:hover:not(:disabled) {
		background-color: var(--color-accent);
	}

	.ingested-menu-dropdown .menu-item:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}
</style>
