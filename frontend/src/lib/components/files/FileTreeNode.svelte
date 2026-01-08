<script lang="ts">
	import { tick } from 'svelte';
	import {
		ChevronRight,
		ChevronDown,
		FileText,
		Folder,
		FolderOpen,
		GripVertical
	} from 'lucide-svelte';
	import { treeStore } from '$lib/stores/tree';
	import { editorStore } from '$lib/stores/editor';
	import DeleteDialogController from '$lib/components/files/DeleteDialogController.svelte';
	import FileTreeContextMenu from '$lib/components/files/FileTreeContextMenu.svelte';
	import { useFileActions } from '$lib/hooks/useFileActions';
	import type { FileNode } from '$lib/types/file';

	export let node: FileNode;
	export let level: number = 0;
	export let onToggle: (path: string) => void;
	export let basePath: string = 'documents';
	export let hideExtensions: boolean = false;
	export let onFileClick: ((path: string) => void) | undefined = undefined;
	export let showActions: boolean = true;
	export let forceExpand: boolean = false;
	export let showGrabHandle: boolean = false;
	export let isDragOver: boolean = false;
	export let isDragging: boolean = false;
	export let onGrabStart: ((event: DragEvent) => void) | undefined = undefined;
	export let onGrabOver: ((event: DragEvent) => void) | undefined = undefined;
	export let onGrabDrop: ((event: DragEvent) => void) | undefined = undefined;
	export let onGrabEnd: (() => void) | undefined = undefined;

	let isEditing = false;
	let editedName = node.name;
	let deleteDialog: { openDialog: (name: string) => void } | null = null;
	let editInput: HTMLInputElement | null = null;
	let folderOptions: { label: string; value: string; depth: number }[] = [];

	$: isExpanded = forceExpand || node.expanded || false;
	$: hasChildren = node.children && node.children.length > 0;
	$: itemType = node.type === 'directory' ? 'folder' : 'file';

	// Display name: remove extension for files if hideExtensions is true
	$: displayName =
		hideExtensions && node.type === 'file' ? node.name.replace(/\.[^/.]+$/, '') : node.name;

	const actions = useFileActions({
		getNode: () => node,
		getBasePath: () => basePath,
		getHideExtensions: () => hideExtensions,
		getEditedName: () => editedName,
		setEditedName: (value) => (editedName = value),
		setIsEditing: (value) => (isEditing = value),
		requestDelete: () => deleteDialog?.openDialog(node.name),
		setFolderOptions: (value) => (folderOptions = value),
		getDisplayName: () => displayName,
		editorStore,
		treeStore
	});

	function handleClick() {
		if (node.type === 'directory') {
			onToggle(node.path);
		} else if (node.type === 'file' && onFileClick) {
			onFileClick(node.path);
		}
	}

	function handleDragOver(event: DragEvent) {
		if (!onGrabOver) return;
		onGrabOver(event);
	}

	function handleDrop(event: DragEvent) {
		if (!onGrabDrop) return;
		onGrabDrop(event);
	}

	const handleRenameKeydown = (event: KeyboardEvent) => {
		if (event.key === 'Escape') {
			actions.cancelRename();
		} else if (event.key === 'Enter') {
			actions.saveRename();
		}
	};

	$: if (isEditing) {
		tick().then(() => {
			editInput?.focus();
			editInput?.select();
		});
	}
</script>

<DeleteDialogController bind:this={deleteDialog} {itemType} onConfirm={actions.confirmDelete} />

<div
	class="tree-node"
	class:drag-over={isDragOver}
	class:dragging={isDragging}
	style="padding-left: {level * 1}rem;"
	role="listitem"
	aria-label={`Pinned note ${displayName}`}
	ondragover={handleDragOver}
	ondrop={handleDrop}
>
	<div class="node-content">
		<button class="node-button" class:expandable={node.type === 'directory'} onclick={handleClick}>
			{#if node.type === 'directory'}
				<span class="chevron">
					{#if isExpanded}
						<ChevronDown size={16} />
					{:else}
						<ChevronRight size={16} />
					{/if}
				</span>
				<span class="icon">
					{#if isExpanded}
						<FolderOpen size={16} />
					{:else}
						<Folder size={16} />
					{/if}
				</span>
			{:else}
				<span class="icon file-icon">
					<FileText size={16} />
				</span>
			{/if}
			{#if isEditing}
				<input
					type="text"
					class="name-input"
					bind:this={editInput}
					bind:value={editedName}
					onblur={actions.saveRename}
					onkeydown={handleRenameKeydown}
					onclick={(e) => e.stopPropagation()}
				/>
			{:else}
				<span class="name">{displayName}</span>
			{/if}
		</button>

		{#if showActions}
			<div class="actions">
				{#if showGrabHandle && node.type === 'file'}
					<button
						class="grab-handle"
						draggable="true"
						ondragstart={onGrabStart}
						ondragend={onGrabEnd}
						onclick={(event) => event.stopPropagation()}
						aria-label="Reorder pinned note"
					>
						<GripVertical size={14} />
					</button>
				{/if}
				<FileTreeContextMenu
					{node}
					{basePath}
					{folderOptions}
					onRename={actions.startRename}
					onDelete={actions.openDeleteDialog}
					onMoveOpen={actions.buildFolderOptions}
					onMoveFile={actions.handleMove}
					onMoveFolder={actions.handleMoveFolder}
					onPinToggle={actions.handlePinToggle}
					onArchive={actions.handleArchive}
					onUnarchive={actions.handleUnarchive}
					onDownload={actions.handleDownload}
				/>
			</div>
		{/if}
	</div>
</div>

{#if isExpanded && hasChildren}
	{#each node.children as child}
		<svelte:self
			node={child}
			level={level + 1}
			{onToggle}
			{basePath}
			{hideExtensions}
			{onFileClick}
			{showActions}
			{forceExpand}
		/>
	{/each}
{/if}

<style>
	.tree-node {
		user-select: none;
		position: relative;
	}

	.node-content {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}

	.tree-node.drag-over {
		background: none;
	}

	.tree-node.drag-over::before {
		content: '';
		position: absolute;
		left: 0.5rem;
		right: 0.5rem;
		top: 0;
		height: 2px;
		border-radius: 999px;
		background: var(--color-sidebar-border);
	}

	.grab-handle {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		border: none;
		background: none;
		color: var(--color-muted-foreground);
		padding: 0.25rem;
		border-radius: 0.375rem;
		cursor: grab;
		opacity: 0;
		pointer-events: none;
		transition: opacity 0.2s ease;
	}

	.grab-handle:active {
		cursor: grabbing;
	}

	.node-content:hover .grab-handle {
		opacity: 0.9;
		pointer-events: auto;
	}

	.node-button {
		display: flex;
		align-items: center;
		gap: 0.375rem;
		flex: 1;
		padding: 0.375rem 0.5rem;
		background: none;
		border: none;
		cursor: pointer;
		font-size: 0.875rem;
		color: var(--color-sidebar-foreground);
		transition: background-color 0.2s;
		text-align: left;
		min-width: 0;
	}

	.node-content:hover .node-button {
		background-color: var(--color-sidebar-accent);
	}

	.node-button.expandable {
		cursor: pointer;
	}

	.chevron {
		display: flex;
		align-items: center;
		color: var(--color-muted-foreground);
	}

	.icon {
		display: flex;
		align-items: center;
		color: var(--color-sidebar-foreground);
	}

	.file-icon {
		margin-left: 1rem;
		color: var(--color-muted-foreground);
	}

	.name {
		flex: 1;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.name-input {
		flex: 1;
		font-size: 0.875rem;
		padding: 0.25rem 0.5rem;
		background-color: var(--color-sidebar-accent);
		color: var(--color-sidebar-foreground);
		border: 1px solid var(--color-sidebar-border);
		border-radius: 0.25rem;
		outline: none;
	}

	.name-input:focus {
		border-color: var(--color-sidebar-primary);
	}

	.actions {
		position: relative;
		display: flex;
		align-items: center;
	}
</style>
