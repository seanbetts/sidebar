<script lang="ts">
	import { Folder } from 'lucide-svelte';
	import { onDestroy, onMount } from 'svelte';
	import { treeStore } from '$lib/stores/tree';
	import { ingestionStore } from '$lib/stores/ingestion';
	import { ingestionViewerStore } from '$lib/stores/ingestion-viewer';
	import { websitesStore } from '$lib/stores/websites';
	import { editorStore, currentNoteId } from '$lib/stores/editor';
	import { useIngestionActions } from '$lib/hooks/useIngestionActions';
	import SidebarLoading from '$lib/components/left-sidebar/SidebarLoading.svelte';
	import SidebarEmptyState from '$lib/components/left-sidebar/SidebarEmptyState.svelte';
	import FilesPinnedSection from '$lib/components/left-sidebar/files/FilesPinnedSection.svelte';
	import FilesCategorySection from '$lib/components/left-sidebar/files/FilesCategorySection.svelte';
	import FilesUploadsSection from '$lib/components/left-sidebar/files/FilesUploadsSection.svelte';
	import {
		categoryLabels,
		categoryOrder,
		iconForCategory,
		stripExtension
	} from '$lib/components/left-sidebar/files/filesPanelUtils';
	import TextInputDialog from '$lib/components/left-sidebar/dialogs/TextInputDialog.svelte';
	import DeleteDialogController from '$lib/components/files/DeleteDialogController.svelte';
	import type { IngestionListItem } from '$lib/types/ingestion';
	const { deleteIngestion, updatePinned, updatePinnedOrder, downloadFile, renameFile } =
		useIngestionActions();

	const basePath = 'documents';

	$: treeData = $treeStore.trees[basePath];
	$: children = treeData?.children || [];
	$: searchQuery = treeData?.searchQuery || '';
	// Show loading if explicitly loading OR if tree hasn't been initialized yet OR if ingestion is loading
	$: loading = (treeData?.loading ?? !treeData) || $ingestionStore.loading;
	$: normalizedQuery = searchQuery.trim().toLowerCase();
	$: processingItems = ($ingestionStore.items || []).filter(
		(item) => !['ready', 'failed', 'canceled'].includes(item.job.status || '')
	);
	$: failedItems = ($ingestionStore.items || []).filter((item) => item.job.status === 'failed');
	$: readyItems = ($ingestionStore.items || []).filter(
		(item) => item.job.status === 'ready' && item.recommended_viewer
	);
	$: filteredProcessingItems = normalizedQuery
		? processingItems.filter((item) =>
				(item.file.filename_original || '').toLowerCase().includes(normalizedQuery)
			)
		: processingItems;
	$: filteredFailedItems = normalizedQuery
		? failedItems.filter((item) =>
				(item.file.filename_original || '').toLowerCase().includes(normalizedQuery)
			)
		: failedItems;
	$: filteredReadyItems = normalizedQuery
		? readyItems.filter((item) =>
				(item.file.filename_original || '').toLowerCase().includes(normalizedQuery)
			)
		: readyItems;
	$: pinnedItems = filteredReadyItems.filter((item) => item.file.pinned);
	$: pinnedItemsSorted = [...pinnedItems].sort((a, b) => {
		const aOrder =
			typeof a.file.pinned_order === 'number' ? a.file.pinned_order : Number.POSITIVE_INFINITY;
		const bOrder =
			typeof b.file.pinned_order === 'number' ? b.file.pinned_order : Number.POSITIVE_INFINITY;
		if (aOrder !== bOrder) return aOrder - bOrder;
		return (a.file.created_at || '').localeCompare(b.file.created_at || '');
	});
	$: unpinnedReadyItems = filteredReadyItems.filter((item) => !item.file.pinned);
	$: categorizedItems = unpinnedReadyItems.reduce<Record<string, IngestionListItem[]>>(
		(acc, item) => {
			const category = item.file.category || 'other';
			if (!acc[category]) acc[category] = [];
			acc[category].push(item);
			return acc;
		},
		{}
	);

	$: showPinnedSection = !searchQuery || pinnedItems.length > 0;
	let expandedCategories = new Set<string>();
	let openMenuKey: string | null = null;
	let isRenameOpen = false;
	let renameValue = '';
	let renameItem: IngestionListItem | null = null;
	let isRenaming = false;
	let deleteDialog: { openDialog: (name: string) => void } | null = null;
	let deleteItem: IngestionListItem | null = null;
	const PINNED_DROP_END = '__end__';
	let draggingPinnedId: string | null = null;
	let dragOverPinnedId: string | null = null;

	function openViewer(item: IngestionListItem) {
		if (!item.recommended_viewer) return;
		websitesStore.clearActive();
		editorStore.reset();
		currentNoteId.set(null);
		ingestionViewerStore.open(item.file.id);
	}

	function requestDelete(item: IngestionListItem, event?: MouseEvent) {
		event?.stopPropagation();
		deleteItem = item;
		deleteDialog?.openDialog(item.file.filename_original ?? 'file');
		openMenuKey = null;
	}

	async function confirmDelete(): Promise<boolean> {
		if (!deleteItem) return false;
		const fileId = deleteItem.file.id;
		try {
			return await deleteIngestion(fileId, { scope: 'FilesPanelController.delete' });
		} finally {
			deleteItem = null;
		}
	}

	onMount(() => {
		ingestionStore.startPolling();
		const handleDocumentClick = (event: MouseEvent) => {
			if (!openMenuKey) return;
			const target = event.target as HTMLElement | null;
			const root = target?.closest<HTMLElement>('[data-ingested-menu-root]');
			if (!root || root.dataset.ingestedMenuRoot !== openMenuKey) {
				openMenuKey = null;
			}
		};
		document.addEventListener('click', handleDocumentClick);
		return () => document.removeEventListener('click', handleDocumentClick);
	});

	onDestroy(() => {
		ingestionStore.stopPolling();
	});

	// Data loading is now handled by parent Sidebar component
	// onMount removed to prevent duplicate loads and initial flicker

	function toggleCategory(category: string) {
		const next = new Set(expandedCategories);
		if (next.has(category)) {
			next.delete(category);
		} else {
			next.add(category);
		}
		expandedCategories = next;
	}

	function toggleMenu(event: MouseEvent, menuKey: string) {
		event.stopPropagation();
		openMenuKey = openMenuKey === menuKey ? null : menuKey;
	}

	async function handlePinToggle(item: IngestionListItem) {
		const nextPinned = !item.file.pinned;
		await updatePinned(item.file.id, nextPinned, { scope: 'FilesPanelController.pin' });
		openMenuKey = null;
	}

	function handlePinnedDragStart(event: DragEvent, fileId: string) {
		draggingPinnedId = fileId;
		dragOverPinnedId = null;
		event.dataTransfer?.setData('text/plain', fileId);
		event.dataTransfer!.effectAllowed = 'move';
	}

	function handlePinnedDragOver(event: DragEvent, fileId: string) {
		if (!draggingPinnedId) return;
		event.preventDefault();
		dragOverPinnedId = fileId;
	}

	async function handlePinnedDrop(event: DragEvent, targetId: string) {
		if (!draggingPinnedId) return;
		event.preventDefault();
		const sourceId = draggingPinnedId;
		draggingPinnedId = null;
		dragOverPinnedId = null;
		if (sourceId === targetId) return;
		const order = pinnedItemsSorted.map((item) => item.file.id);
		const fromIndex = order.indexOf(sourceId);
		const toIndex = order.indexOf(targetId);
		if (fromIndex === -1 || toIndex === -1) return;
		const nextOrder = [...order];
		nextOrder.splice(toIndex, 0, nextOrder.splice(fromIndex, 1)[0]);
		await updatePinnedOrder(nextOrder, { scope: 'FilesPanelController.pinOrder' });
	}

	async function handlePinnedDropEnd(event: DragEvent) {
		if (!draggingPinnedId) return;
		event.preventDefault();
		const sourceId = draggingPinnedId;
		draggingPinnedId = null;
		dragOverPinnedId = null;
		const order = pinnedItemsSorted.map((item) => item.file.id);
		const fromIndex = order.indexOf(sourceId);
		if (fromIndex === -1) return;
		const nextOrder = [...order];
		nextOrder.push(nextOrder.splice(fromIndex, 1)[0]);
		await updatePinnedOrder(nextOrder, { scope: 'FilesPanelController.pinOrder' });
	}

	function handlePinnedDragEnd() {
		draggingPinnedId = null;
		dragOverPinnedId = null;
	}

	async function handleDownload(item: IngestionListItem) {
		if (!item.recommended_viewer) return;
		await downloadFile(item, { scope: 'FilesPanelController.download' });
		openMenuKey = null;
	}

	function handleDelete(item: IngestionListItem, event?: MouseEvent) {
		requestDelete(item, event);
	}

	async function handleRename(item: IngestionListItem) {
		renameItem = item;
		renameValue = stripExtension(item.file.filename_original);
		isRenameOpen = true;
		openMenuKey = null;
	}

	async function confirmRename() {
		if (!renameItem) return;
		const original = renameItem.file.filename_original;
		const extensionMatch = original.match(/\.[^/.]+$/);
		const extension = extensionMatch ? extensionMatch[0] : '';
		const trimmed = renameValue.trim();
		if (!trimmed) return;
		const filename = extension && !trimmed.endsWith(extension) ? `${trimmed}${extension}` : trimmed;
		isRenaming = true;
		try {
			const renamed = await renameFile(renameItem.file.id, filename, {
				scope: 'FilesPanelController.rename'
			});
			if (renamed) {
				isRenameOpen = false;
				renameItem = null;
			}
		} finally {
			isRenaming = false;
		}
	}
</script>

<DeleteDialogController bind:this={deleteDialog} itemType="file" onConfirm={confirmDelete} />

{#if loading}
	<SidebarLoading message="Loading files..." />
{:else if treeData?.error}
	<SidebarEmptyState icon={Folder} title="Service unavailable" subtitle="Please try again later." />
{:else if children.length === 0 && filteredProcessingItems.length === 0 && filteredFailedItems.length === 0 && filteredReadyItems.length === 0}
	<SidebarEmptyState
		icon={Folder}
		title="No files yet"
		subtitle="Upload or create a file to get started."
	/>
{:else}
	<div class="workspace-list">
		<div class="workspace-main">
			{#if showPinnedSection}
				<FilesPinnedSection
					pinnedItems={pinnedItemsSorted}
					{dragOverPinnedId}
					{openMenuKey}
					pinnedDropEndId={PINNED_DROP_END}
					{iconForCategory}
					{stripExtension}
					onOpen={openViewer}
					onToggleMenu={toggleMenu}
					onRename={handleRename}
					onPinToggle={handlePinToggle}
					onDownload={handleDownload}
					onDelete={handleDelete}
					onDragStart={handlePinnedDragStart}
					onDragOver={handlePinnedDragOver}
					onDrop={handlePinnedDrop}
					onDropEnd={handlePinnedDropEnd}
					onDragEnd={handlePinnedDragEnd}
				/>
			{/if}
			<FilesCategorySection
				{searchQuery}
				{categoryOrder}
				{categoryLabels}
				{categorizedItems}
				{expandedCategories}
				{stripExtension}
				{iconForCategory}
				hasReadyItems={filteredReadyItems.length > 0}
				hasSearchResults={filteredReadyItems.length > 0}
				onToggleCategory={toggleCategory}
				onOpen={openViewer}
				onToggleMenu={toggleMenu}
				onRename={handleRename}
				onPinToggle={handlePinToggle}
				onDownload={handleDownload}
				onDelete={handleDelete}
				{openMenuKey}
			/>
		</div>
		<FilesUploadsSection
			processingItems={filteredProcessingItems}
			failedItems={filteredFailedItems}
			{readyItems}
			{openMenuKey}
			{iconForCategory}
			{stripExtension}
			onOpen={openViewer}
			onToggleMenu={toggleMenu}
			onRename={handleRename}
			onPinToggle={handlePinToggle}
			onDownload={handleDownload}
			onDelete={handleDelete}
		/>
	</div>
{/if}

<TextInputDialog
	bind:open={isRenameOpen}
	title="Rename file"
	description="Update the file name."
	placeholder="File name"
	bind:value={renameValue}
	confirmLabel="Rename"
	cancelLabel="Cancel"
	busyLabel="Renaming..."
	isBusy={isRenaming}
	onConfirm={confirmRename}
	onCancel={() => {
		isRenameOpen = false;
		renameItem = null;
	}}
/>

<style>
	.workspace-list {
		display: flex;
		flex-direction: column;
		gap: 1rem;
		padding-top: 0.5rem;
		min-height: 0;
		flex: 1;
	}

	.workspace-main {
		display: flex;
		flex-direction: column;
		gap: 1rem;
		min-height: 0;
		flex: 1;
	}
</style>
