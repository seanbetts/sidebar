<script lang="ts">
	import { ChevronRight, FileText, Search } from 'lucide-svelte';
	import { treeStore } from '$lib/stores/tree';
	import SidebarLoading from '$lib/components/left-sidebar/SidebarLoading.svelte';
	import SidebarEmptyState from '$lib/components/left-sidebar/SidebarEmptyState.svelte';
	import FileTreeNode from '$lib/components/files/FileTreeNode.svelte';
	import * as Collapsible from '$lib/components/ui/collapsible/index.js';
	import type { FileNode } from '$lib/types/file';
	import { useNoteActions } from '$lib/hooks/useNoteActions';

	export let basePath: string = 'notes';
	export let emptyMessage: string = 'No notes found';
	export let hideExtensions: boolean = false;
	export let onFileClick: ((path: string) => void) | undefined = undefined;

	$: treeData = $treeStore.trees[basePath];
	$: children = treeData?.children || [];
	// Show loading if explicitly loading OR if tree hasn't been initialized yet
	$: loading = treeData?.loading ?? !treeData;

	const ARCHIVE_FOLDER = 'Archive';

	// Data loading is now handled by parent Sidebar component
	// onMount removed to prevent duplicate loads and initial flicker

	function handleToggle(path: string) {
		treeStore.toggleExpanded(basePath, path);
	}

	function collectPinned(
		nodes: FileNode[],
		archived: boolean = false,
		acc: FileNode[] = []
	): FileNode[] {
		for (const node of nodes) {
			const isArchive = archived || (node.type === 'directory' && node.name === ARCHIVE_FOLDER);
			if (node.type === 'file' && node.pinned && !isArchive) {
				acc.push(node);
			}
			if (node.children && node.children.length > 0) {
				collectPinned(node.children, isArchive, acc);
			}
		}
		return acc;
	}

	function filterNodes(
		nodes: FileNode[],
		options: { excludePinned: boolean; excludeArchive: boolean },
		archived: boolean = false
	): FileNode[] {
		const results: FileNode[] = [];

		for (const node of nodes) {
			const isArchive = archived || (node.type === 'directory' && node.name === ARCHIVE_FOLDER);
			if (options.excludeArchive && isArchive) {
				continue;
			}
			if (options.excludePinned && node.type === 'file' && node.pinned) {
				continue;
			}

			if (node.type === 'directory') {
				const filteredChildren = filterNodes(node.children || [], options, isArchive);
				if (filteredChildren.length === 0 && !node.folderMarker) {
					continue;
				}
				results.push({ ...node, children: filteredChildren });
			} else {
				results.push(node);
			}
		}

		return results;
	}

	function getArchiveChildren(nodes: FileNode[]): FileNode[] {
		const archiveNode = nodes.find(
			(node) => node.type === 'directory' && node.name === ARCHIVE_FOLDER
		);
		return archiveNode?.children || [];
	}

	function sortPinnedNodes(nodes: FileNode[]): FileNode[] {
		return [...nodes].sort((a, b) => {
			const aOrder = typeof a.pinned_order === 'number' ? a.pinned_order : Number.POSITIVE_INFINITY;
			const bOrder = typeof b.pinned_order === 'number' ? b.pinned_order : Number.POSITIVE_INFINITY;
			if (aOrder !== bOrder) return aOrder - bOrder;
			return a.name.localeCompare(b.name);
		});
	}

	const PINNED_DROP_END = '__end__';
	let draggingPinnedId: string | null = null;
	let dragOverPinnedId: string | null = null;
	const { updatePinnedOrder } = useNoteActions();

	function handlePinnedDragStart(event: DragEvent, nodeId: string) {
		draggingPinnedId = nodeId;
		dragOverPinnedId = null;
		event.dataTransfer?.setData('text/plain', nodeId);
		event.dataTransfer!.effectAllowed = 'move';
	}

	function handlePinnedDragOver(event: DragEvent, nodeId: string) {
		if (!draggingPinnedId) return;
		event.preventDefault();
		dragOverPinnedId = nodeId;
	}

	async function handlePinnedDrop(event: DragEvent, targetId: string) {
		if (!draggingPinnedId) return;
		event.preventDefault();
		const sourceId = draggingPinnedId;
		draggingPinnedId = null;
		dragOverPinnedId = null;
		if (sourceId === targetId) return;
		const order = pinnedNodes.map((node) => node.path);
		const fromIndex = order.indexOf(sourceId);
		const toIndex = order.indexOf(targetId);
		if (fromIndex === -1 || toIndex === -1) return;
		const nextOrder = [...order];
		nextOrder.splice(toIndex, 0, nextOrder.splice(fromIndex, 1)[0]);
		await updatePinnedOrder(nextOrder, { scope: 'NotesPanel.pinOrder' });
	}

	async function handlePinnedDropEnd(event: DragEvent) {
		if (!draggingPinnedId) return;
		event.preventDefault();
		const sourceId = draggingPinnedId;
		draggingPinnedId = null;
		dragOverPinnedId = null;
		const order = pinnedNodes.map((node) => node.path);
		const fromIndex = order.indexOf(sourceId);
		if (fromIndex === -1) return;
		const nextOrder = [...order];
		nextOrder.push(nextOrder.splice(fromIndex, 1)[0]);
		await updatePinnedOrder(nextOrder, { scope: 'NotesPanel.pinOrder' });
	}

	function handlePinnedDragEnd() {
		draggingPinnedId = null;
		dragOverPinnedId = null;
	}

	$: searchQuery = treeData?.searchQuery || '';
	$: pinnedNodes = sortPinnedNodes(collectPinned(children));
	$: mainNodes = filterNodes(children, { excludePinned: true, excludeArchive: true });
	$: archiveNodes = getArchiveChildren(children);
</script>

{#if loading}
	<SidebarLoading message="Loading notes..." />
{:else if treeData?.error}
	<SidebarEmptyState
		icon={FileText}
		title="Service unavailable"
		subtitle="Please try again later."
	/>
{:else if children.length === 0 && !searchQuery}
	<SidebarEmptyState
		icon={FileText}
		title="No notes yet"
		subtitle="Create a note to get started."
	/>
{:else if searchQuery}
	<div class="notes-sections">
		<div class="notes-block">
			<div class="notes-block-title">Results</div>
			{#if children.length > 0}
				<div class="notes-block-content">
					{#each children as node (node.path)}
						<FileTreeNode
							{node}
							level={0}
							onToggle={handleToggle}
							{basePath}
							{hideExtensions}
							{onFileClick}
						/>
					{/each}
				</div>
			{:else}
				<SidebarEmptyState icon={Search} title="No results" subtitle="Try a different search." />
			{/if}
		</div>
	</div>
{:else}
	<div class="notes-sections">
		<div class="notes-block">
			<div class="notes-block-title">Pinned</div>
			{#if pinnedNodes.length > 0}
				<div class="notes-block-content">
					{#each pinnedNodes as node (node.path)}
						<FileTreeNode
							{node}
							level={0}
							onToggle={handleToggle}
							{basePath}
							{hideExtensions}
							{onFileClick}
							showGrabHandle
							isDragging={draggingPinnedId === node.path}
							isDragOver={dragOverPinnedId === node.path}
							onGrabStart={(event) => handlePinnedDragStart(event, node.path)}
							onGrabOver={(event) => handlePinnedDragOver(event, node.path)}
							onGrabDrop={(event) => handlePinnedDrop(event, node.path)}
							onGrabEnd={handlePinnedDragEnd}
						/>
					{/each}
					<div
						class="pinned-drop-zone"
						class:drag-over={dragOverPinnedId === PINNED_DROP_END}
						role="separator"
						aria-label="Drop pinned note at end"
						ondragover={(event) => handlePinnedDragOver(event, PINNED_DROP_END)}
						ondrop={handlePinnedDropEnd}
					></div>
				</div>
			{:else}
				<div class="notes-empty">No pinned notes</div>
			{/if}
		</div>

		<div class="notes-block">
			<div class="notes-block-title">Notes</div>
			{#if mainNodes.length > 0}
				<div class="notes-block-content">
					{#each mainNodes as node (node.path)}
						<FileTreeNode
							{node}
							level={0}
							onToggle={handleToggle}
							{basePath}
							{hideExtensions}
							{onFileClick}
						/>
					{/each}
				</div>
			{:else}
				<div class="notes-empty">{emptyMessage}</div>
			{/if}
		</div>

		<div class="notes-block notes-archive">
			<Collapsible.Root class="group/collapsible" data-collapsible-root>
				<div
					data-slot="sidebar-group"
					data-sidebar="group"
					class="relative flex w-full min-w-0 flex-col p-2"
				>
					<Collapsible.Trigger
						data-slot="sidebar-group-label"
						data-sidebar="group-label"
						class="archive-trigger"
					>
						<span class="notes-block-title archive-label">Archive</span>
						<span
							class="archive-chevron transition-transform group-data-[state=open]/collapsible:rotate-90"
						>
							<ChevronRight size={16} />
						</span>
					</Collapsible.Trigger>
					<Collapsible.Content data-slot="collapsible-content" class="archive-content pt-1">
						<div
							data-slot="sidebar-group-content"
							data-sidebar="group-content"
							class="w-full text-sm"
						>
							{#if archiveNodes.length > 0}
								<div class="notes-block-content">
									{#each archiveNodes as node (node.path)}
										<FileTreeNode
											{node}
											level={0}
											onToggle={handleToggle}
											{basePath}
											{hideExtensions}
											{onFileClick}
										/>
									{/each}
								</div>
							{:else}
								<div class="notes-empty">No archived notes</div>
							{/if}
						</div>
					</Collapsible.Content>
				</div>
			</Collapsible.Root>
		</div>
	</div>
{/if}

<style>
	.notes-sections {
		display: flex;
		flex-direction: column;
		gap: 1rem;
		flex: 1;
		min-height: 0;
		padding-top: 0.5rem;
	}

	.notes-block {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}

	.notes-archive {
		margin-top: auto;
		border-top: 1px solid var(--color-sidebar-border);
		padding-top: 0;
	}

	.notes-block-title {
		font-size: 0.7rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-muted-foreground);
		font-weight: 600;
		padding: 0 0.25rem;
	}

	:global(.archive-trigger) {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.5rem;
		width: 100%;
		border: none;
		background: none;
		cursor: pointer;
		padding: 1rem 0.25rem;
		border-radius: 0.375rem;
		text-align: left;
	}

	:global(.archive-trigger:hover) {
		background-color: var(--color-sidebar-accent);
	}

	.archive-label {
		color: var(--color-muted-foreground);
	}

	:global(.archive-trigger:hover) .archive-label {
		color: var(--color-foreground);
	}

	:global(.archive-chevron) {
		width: 16px;
		height: 16px;
		flex-shrink: 0;
		color: var(--color-muted-foreground);
	}

	:global(.archive-trigger:hover) :global(.archive-chevron) {
		color: var(--color-foreground);
	}

	:global(.archive-content) {
		max-height: min(80vh, 720px);
		overflow-y: auto;
		padding-right: 0.25rem;
	}

	.notes-block-content {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}

	.pinned-drop-zone {
		position: relative;
		height: 12px;
	}

	.pinned-drop-zone.drag-over::before {
		content: '';
		position: absolute;
		left: 0.5rem;
		right: 0.5rem;
		bottom: 0;
		height: 2px;
		border-radius: 999px;
		background: var(--color-sidebar-border);
	}

	.notes-empty {
		padding: 0.5rem 0.25rem;
		color: var(--color-muted-foreground);
		font-size: 0.8rem;
	}
</style>
