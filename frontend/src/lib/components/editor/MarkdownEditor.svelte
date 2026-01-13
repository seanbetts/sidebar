<script lang="ts">
	import { onMount, onDestroy, tick } from 'svelte';
	import type { Editor } from '@tiptap/core';
	import { editorStore } from '$lib/stores/editor';
	import { treeStore } from '$lib/stores/tree';
	import { toast } from 'svelte-sonner';
	import { FileText } from 'lucide-svelte';
	import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';
	import DeleteDialogController from '$lib/components/files/DeleteDialogController.svelte';
	import EditorToolbar from '$lib/components/editor/EditorToolbar.svelte';
	import { createMarkdownEditor } from '$lib/components/editor/useMarkdownEditor';
	import { useEditorActions } from '$lib/hooks/useEditorActions';
	import { useLeaveGuard } from '$lib/hooks/useLeaveGuard';

	// Module-level map to persist scroll positions across remounts
	const scrollPositions = new Map<string, number>();

	let editorElement: HTMLDivElement;
	let editor: Editor | null = null;
	let saveTimeout: ReturnType<typeof setTimeout>;
	let destroyEditor: (() => void) | null = null;

	let isLeaveDialogOpen = false;
	let pendingHref: string | null = null;
	let allowNavigateOnce = false;
	let isRenameDialogOpen = false;
	let renameValue = '';
	let renameInput: HTMLInputElement | null = null;
	let deleteDialog: { openDialog: (name: string) => void } | null = null;
	let isSaveBeforeCloseDialogOpen = false;
	let isSaveBeforeRenameDialogOpen = false;
	let folderOptions: { label: string; value: string; depth: number }[] = [];
	let copyTimeout: ReturnType<typeof setTimeout> | null = null;
	let isCopied = false;
	let savedIndicatorTimeout: ReturnType<typeof setTimeout> | null = null;
	let showSavedIndicator = true;
	let editorScrollElement: HTMLDivElement;

	$: isDirty = $editorStore.isDirty;
	$: isSaving = $editorStore.isSaving;
	$: lastSaved = $editorStore.lastSaved;
	$: saveError = $editorStore.saveError;
	$: currentNoteName = $editorStore.currentNoteName;
	$: isLoading = $editorStore.isLoading;
	$: currentNoteId = $editorStore.currentNoteId;
	$: isReadOnly = $editorStore.isReadOnly;

	// Strip file extension from note name for display
	$: displayTitle = currentNoteName ? currentNoteName.replace(/\.[^/.]+$/, '') : '';

	function findNoteNode(noteId: string | null, tree: any) {
		if (!noteId) return null;
		const nodes = tree?.children || [];
		const walk = (items: any[]): any | null => {
			for (const item of items) {
				if (item.type === 'file' && item.path === noteId) return item;
				if (item.children) {
					const match = walk(item.children);
					if (match) return match;
				}
			}
			return null;
		};
		return walk(nodes);
	}

	$: noteNode = findNoteNode(currentNoteId, $treeStore.trees['notes']);

	const actions = useEditorActions({
		editorStore,
		treeStore,
		getCurrentNoteId: () => currentNoteId,
		getDisplayTitle: () => displayTitle,
		getNoteNode: () => noteNode,
		getIsDirty: () => isDirty,
		getRenameValue: () => renameValue,
		setRenameValue: (value) => (renameValue = value),
		setIsSaveBeforeCloseDialogOpen: (value) => (isSaveBeforeCloseDialogOpen = value),
		setIsSaveBeforeRenameDialogOpen: (value) => (isSaveBeforeRenameDialogOpen = value),
		setIsRenameDialogOpen: (value) => (isRenameDialogOpen = value),
		setFolderOptions: (value) => (folderOptions = value),
		getCopyTimeout: () => copyTimeout,
		setCopyTimeout: (value) => (copyTimeout = value),
		setIsCopied: (value) => (isCopied = value)
	});

	onMount(() => {
		const { editor: createdEditor, destroy } = createMarkdownEditor({
			element: editorElement,
			editorStore,
			onAutosave: scheduleAutoSave,
			onExternalUpdate: () => toast.message('Note updated')
		});
		editor = createdEditor;
		destroyEditor = destroy;

		// Restore scroll position after content is rendered
		if (currentNoteId && editorScrollElement) {
			const savedPosition = scrollPositions.get(currentNoteId) ?? 0;
			requestAnimationFrame(() => {
				requestAnimationFrame(() => {
					if (editorScrollElement) {
						editorScrollElement.scrollTop = savedPosition;
					}
				});
			});
		}
	});

	const { stayOnPage, confirmLeave } = useLeaveGuard({
		isDirty: () => $editorStore.isDirty,
		getAllowNavigateOnce: () => allowNavigateOnce,
		getPendingHref: () => pendingHref,
		setPendingHref: (value) => (pendingHref = value),
		setIsLeaveDialogOpen: (value) => (isLeaveDialogOpen = value),
		setAllowNavigateOnce: (value) => (allowNavigateOnce = value)
	});

	$: if (isRenameDialogOpen) {
		tick().then(() => {
			renameInput?.focus();
			renameInput?.select();
		});
	}

	$: if (editor) {
		editor.setEditable(!isReadOnly);
	}

	function requestDelete() {
		if (!currentNoteName) return;
		deleteDialog?.openDialog(displayTitle || currentNoteName);
	}

	onDestroy(() => {
		// Save scroll position before unmounting
		if (currentNoteId && editorScrollElement) {
			scrollPositions.set(currentNoteId, editorScrollElement.scrollTop);
		}

		// Cleanup all timers and subscriptions
		clearTimeout(saveTimeout);
		if (copyTimeout) clearTimeout(copyTimeout);
		if (savedIndicatorTimeout) clearTimeout(savedIndicatorTimeout);
		if (destroyEditor) destroyEditor();
	});

	function scheduleAutoSave() {
		clearTimeout(saveTimeout);
		if ($editorStore.isDirty && !$editorStore.isReadOnly) {
			saveTimeout = setTimeout(() => {
				editorStore.saveNote();
			}, 1500);
		}
	}

	function formatLastSaved(date: Date | null, show: boolean): string {
		if (!date || !show) return '';
		const now = new Date();
		const diffMs = now.getTime() - date.getTime();
		const diffSecs = Math.floor(diffMs / 1000);

		if (diffSecs < 60) return 'just now';
		if (diffSecs < 3600) return `${Math.floor(diffSecs / 60)}m ago`;
		return date.toLocaleTimeString(undefined, {
			hour: '2-digit',
			minute: '2-digit',
			hour12: false
		});
	}

	// Track the timestamp (not the Date object) to detect actual changes
	let hideScheduledForTimestamp: number = 0;

	$: {
		const currentTimestamp = lastSaved?.getTime() || 0;

		// Only trigger auto-hide when we have a new save timestamp
		if (
			currentTimestamp > 0 &&
			currentTimestamp !== hideScheduledForTimestamp &&
			!isDirty &&
			!isSaving
		) {
			hideScheduledForTimestamp = currentTimestamp;
			showSavedIndicator = true;

			// Clear any existing timeout
			if (savedIndicatorTimeout) {
				clearTimeout(savedIndicatorTimeout);
				savedIndicatorTimeout = null;
			}

			// Schedule auto-hide after 2 seconds
			savedIndicatorTimeout = setTimeout(() => {
				showSavedIndicator = false;
			}, 2000);
		}

		// If user starts editing, hide the saved indicator immediately
		if (isDirty) {
			showSavedIndicator = false;
			if (savedIndicatorTimeout) {
				clearTimeout(savedIndicatorTimeout);
				savedIndicatorTimeout = null;
			}
		}
	}

	$: lastSavedLabel = formatLastSaved(lastSaved, showSavedIndicator);

	// Save and restore scroll position when switching notes (not on mount/unmount)
	let previousNoteId: string | null = null;
	let isInitialMount = true;
	$: {
		// Skip the initial mount - onMount handles that
		if (isInitialMount && currentNoteId) {
			previousNoteId = currentNoteId;
			isInitialMount = false;
		} else if (editorScrollElement && previousNoteId && previousNoteId !== currentNoteId) {
			// Save previous note's scroll position
			scrollPositions.set(previousNoteId, editorScrollElement.scrollTop);

			// Restore new note's scroll position
			if (currentNoteId) {
				const savedPosition = scrollPositions.get(currentNoteId) ?? 0;
				requestAnimationFrame(() => {
					requestAnimationFrame(() => {
						if (editorScrollElement) {
							editorScrollElement.scrollTop = savedPosition;
						}
					});
				});
			}
			previousNoteId = currentNoteId;
		}
	}
</script>

<AlertDialog.Root bind:open={isLeaveDialogOpen}>
	<AlertDialog.Content>
		<AlertDialog.Header>
			<AlertDialog.Title>Leave without saving?</AlertDialog.Title>
			<AlertDialog.Description>
				You have unsaved changes. If you leave now, they will be lost.
			</AlertDialog.Description>
		</AlertDialog.Header>
		<AlertDialog.Footer>
			<AlertDialog.Cancel onclick={stayOnPage}>Stay</AlertDialog.Cancel>
			<AlertDialog.Action onclick={confirmLeave}>Leave</AlertDialog.Action>
		</AlertDialog.Footer>
	</AlertDialog.Content>
</AlertDialog.Root>

<AlertDialog.Root bind:open={isRenameDialogOpen}>
	<AlertDialog.Content
		onOpenAutoFocus={(event) => {
			event.preventDefault();
			renameInput?.focus();
			renameInput?.select();
		}}
	>
		<AlertDialog.Header>
			<AlertDialog.Title>Rename note</AlertDialog.Title>
			<AlertDialog.Description>Update the note title.</AlertDialog.Description>
		</AlertDialog.Header>
		<div class="py-2">
			<input
				class="w-full rounded-md border bg-background px-3 py-2 text-sm shadow-sm outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
				type="text"
				placeholder="Note title"
				bind:this={renameInput}
				bind:value={renameValue}
				on:keydown={(event) => {
					if (event.key === 'Enter') actions.handleRename();
				}}
			/>
		</div>
		<AlertDialog.Footer>
			<AlertDialog.Cancel onclick={() => (isRenameDialogOpen = false)}>Cancel</AlertDialog.Cancel>
			<AlertDialog.Action disabled={!renameValue.trim()} onclick={actions.handleRename}>
				Rename
			</AlertDialog.Action>
		</AlertDialog.Footer>
	</AlertDialog.Content>
</AlertDialog.Root>

<DeleteDialogController bind:this={deleteDialog} itemType="note" onConfirm={actions.handleDelete} />

<AlertDialog.Root bind:open={isSaveBeforeCloseDialogOpen}>
	<AlertDialog.Content>
		<AlertDialog.Header>
			<AlertDialog.Title>Save changes?</AlertDialog.Title>
			<AlertDialog.Description>
				Do you want to save changes before closing this note?
			</AlertDialog.Description>
		</AlertDialog.Header>
		<AlertDialog.Footer>
			<AlertDialog.Cancel onclick={actions.discardAndClose}>Don't Save</AlertDialog.Cancel>
			<AlertDialog.Action onclick={actions.confirmSaveAndClose}>Save</AlertDialog.Action>
		</AlertDialog.Footer>
	</AlertDialog.Content>
</AlertDialog.Root>

<AlertDialog.Root bind:open={isSaveBeforeRenameDialogOpen}>
	<AlertDialog.Content>
		<AlertDialog.Header>
			<AlertDialog.Title>Save changes?</AlertDialog.Title>
			<AlertDialog.Description>
				Do you want to save changes before renaming this note?
			</AlertDialog.Description>
		</AlertDialog.Header>
		<AlertDialog.Footer>
			<AlertDialog.Cancel onclick={actions.discardAndRename}>Don't Save</AlertDialog.Cancel>
			<AlertDialog.Action onclick={actions.confirmSaveAndRename}>Save</AlertDialog.Action>
		</AlertDialog.Footer>
	</AlertDialog.Content>
</AlertDialog.Root>

<div class="editor-container">
	{#if currentNoteName}
		<EditorToolbar
			{displayTitle}
			{lastSavedLabel}
			{isReadOnly}
			{isDirty}
			{isSaving}
			saveError={saveError ?? ''}
			{noteNode}
			{folderOptions}
			{isCopied}
			onCopy={actions.handleCopy}
			onClose={actions.handleClose}
			onPinToggle={actions.handlePinToggle}
			onRename={actions.openRenameDialog}
			onMoveOpen={actions.buildFolderOptions}
			onMove={actions.handleMove}
			onDownload={actions.handleDownload}
			onArchive={actions.handleArchive}
			onUnarchive={actions.handleUnarchive}
			onDelete={requestDelete}
		/>
	{/if}

	<!-- TipTap Editor - always rendered -->
	<div bind:this={editorScrollElement} class="editor-scroll" class:hidden={!currentNoteName}>
		<div bind:this={editorElement} class="tiptap-editor"></div>
	</div>

	<!-- Empty state - shown when no note selected -->
	{#if !currentNoteName}
		<div class="empty-state">
			<img class="welcome-logo" src="/images/logo.svg" alt="sideBar" />
			<h2>Welcome to sideBar</h2>
			<p>Select a note, website, or file to get started</p>
		</div>
	{/if}
</div>

<style>
	.editor-container {
		display: flex;
		flex-direction: column;
		height: 100%;
		min-height: 0;
		background-color: var(--color-background);
	}

	.editor-scroll {
		flex: 1;
		overflow-y: auto;
		padding: 1rem 2rem;
		min-height: 0;
	}

	.editor-scroll.hidden {
		display: none;
	}

	.tiptap-editor {
		max-width: 85ch;
		margin: 0 auto;
	}

	.empty-state {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		height: 100%;
		color: var(--color-muted-foreground);
		text-align: center;
	}

	.welcome-logo {
		height: 4rem;
		width: auto;
		margin: 0 auto 0.75rem;
		opacity: 0.7;
	}

	:global(.dark) .welcome-logo {
		filter: invert(1);
	}

	.empty-state h2 {
		margin-bottom: 0.5rem;
		font-size: 1.25rem;
		font-weight: 600;
	}

	.empty-state p {
		font-size: 0.95rem;
	}

	/* ========================================================================
	   COMPONENT-SPECIFIC: Standard editor layout
	   Main note editor uses optimal line length (85ch) for readability and
	   standard spacing (1.7 line-height, 0.75em margins) for comfortable
	   long-form writing. This serves as the reference implementation.
	   ======================================================================== */

	/* TipTap prose styling */
	:global(.tiptap) {
		outline: none;
		min-height: 100%;
		color: var(--color-foreground);
	}

	:global(.tiptap h1) {
		font-size: 2em;
		font-weight: 700;
		margin-top: 0;
		margin-bottom: 0.5em;
		color: var(--color-foreground);
	}

	:global(.tiptap h2) {
		font-size: 1.5em;
		font-weight: 600;
		margin-top: 0.5em;
		margin-bottom: 0.5em;
		color: var(--color-foreground);
	}

	:global(.tiptap h3) {
		font-size: 1.25em;
		font-weight: 600;
		margin-top: 0.5em;
		margin-bottom: 0.5em;
		color: var(--color-foreground);
	}

	:global(.tiptap p) {
		margin-top: 0.75em;
		margin-bottom: 0.75em;
		line-height: 1.7;
	}

	:global(.tiptap strong) {
		font-weight: 700;
	}

	:global(.tiptap em) {
		font-style: italic;
	}

	:global(.tiptap code) {
		background-color: var(--color-muted);
		color: var(--color-foreground);
		padding: 0.2em 0.4em;
		border-radius: 0.25em;
		font-size: 0.875em;
		font-family:
			ui-monospace, 'Cascadia Code', 'Source Code Pro', Menlo, Consolas, 'DejaVu Sans Mono',
			monospace;
	}

	:global(.tiptap pre) {
		background-color: var(--color-muted);
		color: var(--color-foreground);
		padding: 1em;
		border-radius: 0.5em;
		overflow-x: auto;
		margin: 1em 0;
	}

	:global(.tiptap pre code) {
		background-color: transparent;
		padding: 0;
		font-size: 0.875em;
	}

	:global(.tiptap ul),
	:global(.tiptap ol) {
		margin-top: 0.75em;
		margin-bottom: 0.75em;
		padding-left: 1.5em;
	}

	:global(.tiptap li > ul),
	:global(.tiptap li > ol) {
		margin-top: 0;
		margin-bottom: 0;
	}

	:global(.tiptap ul) {
		list-style-type: disc;
	}

	:global(.tiptap ol) {
		list-style-type: decimal;
	}

	:global(.tiptap li) {
		margin-top: 0 !important;
		margin-bottom: 0 !important;
		line-height: 1.4;
	}

	:global(.tiptap li p) {
		margin-top: 0 !important;
		margin-bottom: 0 !important;
	}

	:global(.tiptap blockquote) {
		border-left: 3px solid var(--color-border);
		padding-left: 1em;
		margin-left: 0;
		margin-top: 1em;
		margin-bottom: 1em;
		color: var(--color-muted-foreground);
	}

	:global(.tiptap hr) {
		border: none;
		border-top: 1px solid var(--color-border);
		margin: 2em 0;
	}

	:global(.tiptap a) {
		color: var(--color-primary);
		text-decoration: underline;
	}

	:global(.tiptap a:hover) {
		cursor: pointer;
		opacity: 0.8;
	}

	/* Spin animation for saving icon */
	:global(.spin) {
		animation: spin 1s linear infinite;
	}

	@keyframes spin {
		from {
			transform: rotate(0deg);
		}
		to {
			transform: rotate(360deg);
		}
	}
</style>
