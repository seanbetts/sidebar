<script lang="ts">
	import { onDestroy, onMount, tick } from 'svelte';
	import { get } from 'svelte/store';
	import { Editor } from '@tiptap/core';
	import StarterKit from '@tiptap/starter-kit';
	import { ImageGallery } from '$lib/components/editor/ImageGallery';
	import { ImageWithCaption } from '$lib/components/editor/ImageWithCaption';
	import { TaskList, TaskItem } from '@tiptap/extension-list';
	import { TableKit } from '@tiptap/extension-table';
	import { Markdown } from 'tiptap-markdown';
	import { memoriesStore } from '$lib/stores/memories';
	import type { Memory } from '$lib/types/memory';
	import { Loader2 } from 'lucide-svelte';
	import MemoryToolbar from '$lib/components/settings/memory/MemoryToolbar.svelte';
	import MemoryTable from '$lib/components/settings/memory/MemoryTable.svelte';
	import MemoryCreateDialog from '$lib/components/settings/memory/MemoryCreateDialog.svelte';
	import MemoryEditDialog from '$lib/components/settings/memory/MemoryEditDialog.svelte';
	import DeleteDialogController from '$lib/components/files/DeleteDialogController.svelte';
	import { logError } from '$lib/utils/errorHandling';

	type MarkdownStorage = {
		markdown: { getMarkdown: () => string };
	};

	let searchTerm = '';
	let showCreateDialog = false;
	let showEditDialog = false;
	let activeMemoryId: string | null = null;
	let createName = '';
	let createContent = '';
	let editorElement: HTMLDivElement | null = null;
	let editor: Editor | null = null;
	let isSyncingEditor = false;
	let deleteDialog: { openDialog: (name: string) => void } | null = null;
	let pendingDelete: Memory | null = null;

	let draftById: Record<string, { path: string; name: string; content: string }> = {};
	let saveStateById: Record<string, 'idle' | 'dirty' | 'saving' | 'saved' | 'error'> = {};
	let saveTimers: Record<string, ReturnType<typeof setTimeout>> = {};

	const resetDrafts = (memories: Memory[]) => {
		const nextDrafts: Record<string, { path: string; name: string; content: string }> = {};
		const nextStates: Record<string, 'idle' | 'dirty' | 'saving' | 'saved' | 'error'> = {};

		for (const memory of memories) {
			const existing = draftById[memory.id];
			const canSync =
				!existing || saveStateById[memory.id] === 'idle' || saveStateById[memory.id] === 'saved';
			if (canSync) {
				nextDrafts[memory.id] = {
					path: memory.path,
					name: displayName(memory.path),
					content: memory.content
				};
				nextStates[memory.id] = saveStateById[memory.id] ?? 'idle';
			} else if (existing) {
				nextDrafts[memory.id] = existing;
				nextStates[memory.id] = saveStateById[memory.id] ?? 'dirty';
			}
		}

		draftById = nextDrafts;
		saveStateById = nextStates;
	};

	onMount(() => {
		memoriesStore.load();
	});

	onDestroy(() => {
		editor?.destroy();
		editor = null;
	});

	$: resetDrafts($memoriesStore.memories);

	function displayName(path: string) {
		let trimmed = path.startsWith('/memories/') ? path.slice('/memories/'.length) : path;
		if (trimmed.endsWith('.md')) trimmed = trimmed.slice(0, -3);
		return trimmed || 'untitled';
	}

	function buildPathFromName(name: string, fallbackPath?: string) {
		const trimmed = name.trim();
		if (!trimmed) return fallbackPath ?? '/memories/untitled.md';
		const basePath = trimmed.replace(/^\/?memories\/?/, '');
		const hasExtension = basePath.split('/').pop()?.includes('.') ?? false;
		if (basePath.includes('/')) {
			return `/memories/${hasExtension ? basePath : `${basePath}.md`}`;
		}
		if (fallbackPath) {
			const lastSlash = fallbackPath.lastIndexOf('/');
			const dir = lastSlash > 0 ? fallbackPath.slice(0, lastSlash + 1) : '/memories/';
			const ext = fallbackPath.includes('.')
				? fallbackPath.slice(fallbackPath.lastIndexOf('.'))
				: '.md';
			return `${dir}${hasExtension ? basePath : `${basePath}${ext}`}`;
		}
		return `/memories/${hasExtension ? basePath : `${basePath}.md`}`;
	}

	async function createMemory() {
		if (!createName.trim() || !createContent.trim()) return;
		const path = buildPathFromName(createName);
		const created = await memoriesStore.create({
			path,
			content: createContent
		});
		if (created) {
			createName = '';
			createContent = '';
			showCreateDialog = false;
		}
	}

	async function openEditor(memory: Memory) {
		activeMemoryId = memory.id;
		showEditDialog = true;
		await tick();
		ensureEditor();
		syncEditorContent();
	}

	function closeEditor() {
		showEditDialog = false;
		activeMemoryId = null;
		editor?.destroy();
		editor = null;
	}

	function scheduleSave(memoryId: string) {
		const draft = draftById[memoryId];
		const memory = get(memoriesStore).memories.find((item) => item.id === memoryId);
		if (!draft || !memory) return;
		const nextPath = buildPathFromName(draft.name, draft.path);
		const nextContent = draft.content;

		if (nextPath === memory.path && nextContent === memory.content) {
			saveStateById[memoryId] = 'idle';
			return;
		}

		saveStateById[memoryId] = 'dirty';
		if (saveTimers[memoryId]) clearTimeout(saveTimers[memoryId]);
		saveTimers[memoryId] = setTimeout(async () => {
			saveStateById[memoryId] = 'saving';
			try {
				await memoriesStore.updateMemory(memoryId, {
					path: nextPath,
					content: nextContent
				});
				saveStateById[memoryId] = 'saved';
				setTimeout(() => {
					if (saveStateById[memoryId] === 'saved') saveStateById[memoryId] = 'idle';
				}, 1200);
			} catch {
				saveStateById[memoryId] = 'error';
			}
		}, 650);
	}

	function requestDelete(memory: Memory) {
		pendingDelete = memory;
		deleteDialog?.openDialog(memory.path || 'memory');
	}

	async function confirmDelete(): Promise<boolean> {
		const deleting = pendingDelete;
		if (!deleting) return false;
		try {
			await memoriesStore.delete(deleting.id);
			if (deleting.id === activeMemoryId) {
				closeEditor();
			}
			pendingDelete = null;
			return true;
		} catch (error) {
			logError('Failed to delete memory', error, {
				scope: 'memorySettings.delete',
				memoryId: deleting.id
			});
			return false;
		}
	}

	function handleDraftNameChange(value: string) {
		if (!activeMemoryId) return;
		const draft = draftById[activeMemoryId];
		if (!draft) return;
		if (draft.name === value) return;
		draftById = {
			...draftById,
			[activeMemoryId]: {
				...draft,
				name: value
			}
		};
		scheduleSave(activeMemoryId);
	}

	function ensureEditor() {
		if (!editorElement || editor) return;
		editor = new Editor({
			element: editorElement,
			extensions: [
				StarterKit,
				ImageGallery,
				ImageWithCaption.configure({ inline: false, allowBase64: true }),
				TaskList,
				TaskItem.configure({ nested: true }),
				TableKit,
				Markdown
			],
			content: '',
			editable: true,
			editorProps: {
				attributes: {
					class: 'tiptap memory-markdown prose prose-sm max-w-none'
				}
			},
			onUpdate: ({ editor }) => {
				if (!activeMemoryId || isSyncingEditor) return;
				const markdown = (
					editor as Editor & { storage: MarkdownStorage }
				).storage.markdown.getMarkdown();
				const draft = draftById[activeMemoryId];
				if (!draft || draft.content === markdown) return;
				draftById = {
					...draftById,
					[activeMemoryId]: {
						...draft,
						content: markdown
					}
				};
				scheduleSave(activeMemoryId);
			}
		});
	}

	function syncEditorContent() {
		if (!editor || !activeMemoryId) return;
		const draft = draftById[activeMemoryId];
		if (!draft) return;
		const current = (
			editor as Editor & { storage: MarkdownStorage }
		).storage.markdown.getMarkdown();
		if (current === draft.content) return;
		isSyncingEditor = true;
		editor.commands.setContent(draft.content || '');
		isSyncingEditor = false;
	}

	$: activeMemory =
		activeMemoryId && $memoriesStore.memories
			? ($memoriesStore.memories.find((memory) => memory.id === activeMemoryId) ?? null)
			: null;

	$: activeDraftName = activeMemoryId ? (draftById[activeMemoryId]?.name ?? '') : '';
	$: activeSaveState = activeMemoryId ? (saveStateById[activeMemoryId] ?? 'idle') : 'idle';

	$: if (showEditDialog && activeMemoryId && editor && draftById[activeMemoryId]) {
		syncEditorContent();
	}

	$: filteredMemories =
		$memoriesStore.memories?.filter((memory) => {
			const draft = draftById[memory.id];
			const name = draft ? draft.name : displayName(memory.path);
			const content = draft ? draft.content : memory.content;
			const haystack = `${name} ${content}`.toLowerCase();
			return haystack.includes(searchTerm.trim().toLowerCase());
		}) ?? [];
</script>

<section class="memory-settings">
	<div class="settings-section-header">
		<h3>Memory</h3>
		<p>Store stable facts about you, projects, and relationships. Avoid preferences.</p>
	</div>

	<MemoryToolbar bind:searchTerm onCreate={() => (showCreateDialog = true)} />

	{#if $memoriesStore.isLoading}
		<div class="settings-meta">
			<Loader2 size={16} class="spin" />
			Loading memories...
		</div>
	{:else if $memoriesStore.error}
		<div class="settings-error">{$memoriesStore.error}</div>
	{:else if $memoriesStore.memories.length === 0}
		<div class="settings-meta">No memories stored yet.</div>
	{:else if filteredMemories.length === 0}
		<div class="settings-meta">No memories match that search.</div>
	{:else}
		<MemoryTable
			memories={filteredMemories}
			{draftById}
			{displayName}
			onEdit={openEditor}
			onDelete={requestDelete}
		/>
	{/if}
</section>

<MemoryCreateDialog
	bind:open={showCreateDialog}
	bind:nameValue={createName}
	bind:contentValue={createContent}
	onCreate={createMemory}
	onClose={() => (showCreateDialog = false)}
/>

<MemoryEditDialog
	open={showEditDialog}
	memory={activeMemory}
	nameValue={activeDraftName}
	saveState={activeSaveState}
	bind:editorElement
	onNameInput={handleDraftNameChange}
	onClose={closeEditor}
	onDelete={() => activeMemory && requestDelete(activeMemory)}
/>

<DeleteDialogController bind:this={deleteDialog} itemType="memory" onConfirm={confirmDelete} />

<style>
	.memory-settings {
		display: flex;
		flex-direction: column;
		gap: 1.5rem;
	}

	.settings-section-header h3 {
		margin: 0 0 0.35rem;
		font-size: 1rem;
		font-weight: 600;
	}

	.settings-section-header p {
		margin: 0 0 0.75rem;
		font-size: 0.85rem;
		color: var(--color-muted-foreground);
	}

	:global(.settings-label) {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
		font-size: 0.8rem;
		color: var(--color-muted-foreground);
	}

	:global(.settings-input),
	:global(.settings-textarea) {
		width: 100%;
		padding: 0.55rem 0.65rem;
		border-radius: 0.5rem;
		border: 1px solid var(--color-border);
		background: var(--color-card);
		color: var(--color-foreground);
		font-size: 0.85rem;
	}

	:global(.settings-textarea) {
		resize: vertical;
	}

	:global(.settings-button) {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		padding: 0.45rem 0.9rem;
		border-radius: 0.55rem;
		border: none;
		background: var(--color-primary);
		color: var(--color-primary-foreground);
		font-size: 0.8rem;
		font-weight: 600;
		cursor: pointer;
		transition: opacity 0.2s ease;
	}

	:global(.settings-button.secondary) {
		background: var(--color-secondary);
		border: 1px solid var(--color-border);
		color: var(--color-secondary-foreground);
	}

	:global(.settings-button.ghost) {
		background: transparent;
		border: 1px solid transparent;
		color: var(--color-muted-foreground);
		padding: 0.35rem 0.5rem;
	}

	:global(.settings-meta) {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		color: var(--color-muted-foreground);
		font-size: 0.8rem;
	}

	:global(.settings-error) {
		color: #c0392b;
		font-size: 0.8rem;
	}

	:global(.memory-modal) {
		position: fixed;
		inset: 0;
		display: grid;
		place-items: center;
		z-index: 50;
	}

	:global(.memory-modal-overlay) {
		position: absolute;
		inset: 0;
		background: rgba(7, 10, 18, 0.6);
	}

	:global(.memory-modal-content) {
		position: relative;
		width: min(720px, 92vw);
		background: var(--color-card);
		border-radius: 1rem;
		padding: 1.5rem;
		border: 1px solid var(--color-border);
		display: flex;
		flex-direction: column;
		gap: 1rem;
		box-shadow: 0 25px 60px rgba(0, 0, 0, 0.2);
	}

	:global(.memory-modal-header) {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: 1rem;
	}

	:global(.memory-modal-header h4) {
		margin: 0;
		font-size: 1.1rem;
	}

	:global(.memory-modal-header p) {
		margin: 0.25rem 0 0;
		font-size: 0.8rem;
		color: var(--color-muted-foreground);
	}

	:global(.memory-modal-actions) {
		display: flex;
		justify-content: flex-end;
		gap: 0.6rem;
	}

	:global(.memory-editor) {
		border: 1px solid var(--color-border);
		border-radius: 0.75rem;
		background: var(--color-background);
	}

	:global(.memory-editor-surface) {
		padding: 0.75rem 0.9rem;
		min-height: 220px;
	}

	:global(.memory-markdown [contenteditable='true']:focus) {
		outline: none;
	}

	:global(.icon-button) {
		border: none;
		background: transparent;
		color: var(--color-muted-foreground);
		cursor: pointer;
		padding: 0.25rem;
	}

	:global(.memory-status) {
		font-size: 0.75rem;
		color: var(--color-muted-foreground);
	}

	:global(.memory-status.saving),
	:global(.memory-status.dirty) {
		color: #d9822b;
	}

	:global(.memory-status.saved) {
		color: #2d9f7f;
	}

	:global(.memory-status.error) {
		color: #c0392b;
	}
</style>
