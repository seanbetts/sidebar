<script lang="ts">
	import { onDestroy } from 'svelte';
	import { Editor } from '@tiptap/core';
	import StarterKit from '@tiptap/starter-kit';
	import { TaskList, TaskItem } from '@tiptap/extension-list';
	import { Markdown } from 'tiptap-markdown';
	import { Pencil } from 'lucide-svelte';
	import { buttonVariants } from '$lib/components/ui/button/index.js';
	import * as Popover from '$lib/components/ui/popover/index.js';

	const scratchpadPath = 'scratchpad.md';
	const scratchpadHeading = '# ✏️ Scratchpad';
	const scratchpadTitle = '✏️ Scratchpad';
	const scratchpadFilename = `${scratchpadTitle}.md`;
	const scratchpadStorageKey = 'scratchpadNoteId';

	let editorElement: HTMLDivElement;
	let editor: Editor | null = null;
	let isOpen = false;
	let isLoading = false;
	let isSaving = false;
	let saveError: string | null = null;
	let lastSavedContent = '';
	let isUpdatingContent = false;
	let saveTimeout: ReturnType<typeof setTimeout> | undefined;
	let isClosing = false;
	let hasUserEdits = false;
	let scratchpadId: string | null = null;

	function stripHeading(markdown: string): string {
		const trimmed = markdown.trim();
		if (!trimmed.startsWith(scratchpadHeading)) return markdown;
		const withoutHeading = trimmed.slice(scratchpadHeading.length).trimStart();
		return withoutHeading.replace(/^\n+/, '');
	}

	function withHeading(markdown: string): string {
		const body = markdown.trim();
		if (!body) return `${scratchpadHeading}\n`;
		return `${scratchpadHeading}\n\n${body}\n`;
	}

	function removeEmptyTaskItems(markdown: string): string {
		return markdown.replace(/^\s*[-*]\s+\[ \]\s*$/gm, '').trim();
	}

	function findScratchpadId(nodes: Array<{ name?: string; path?: string; type?: string; children?: unknown[] }>) {
		for (const node of nodes) {
			if (node.type === 'file' && node.name === scratchpadFilename) {
				return node.path || null;
			}
			if (node.type === 'directory' && Array.isArray(node.children)) {
				const found = findScratchpadId(node.children as Array<{ name?: string; path?: string; type?: string; children?: unknown[] }>);
				if (found) return found;
			}
		}
		return null;
	}

	async function resolveScratchpadId(): Promise<string> {
		if (scratchpadId) return scratchpadId;
		const stored = typeof localStorage !== 'undefined' ? localStorage.getItem(scratchpadStorageKey) : null;
		if (stored) {
			const verify = await fetch(
				`/api/files/content?basePath=notes&path=${encodeURIComponent(stored)}`
			);
			if (verify.ok) {
				scratchpadId = stored;
				return stored;
			}
			localStorage.removeItem(scratchpadStorageKey);
		}

		const treeResponse = await fetch('/api/files?basePath=notes');
		if (treeResponse.ok) {
			const data = await treeResponse.json();
			const found = findScratchpadId(data?.children || []);
			if (found) {
				scratchpadId = found;
				localStorage.setItem(scratchpadStorageKey, found);
				return found;
			}
		}

		const content = `${scratchpadHeading}\n\n`;
		const createResponse = await fetch('/api/files/content', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({
				basePath: 'notes',
				path: scratchpadPath,
				content
			})
		});
		if (!createResponse.ok) throw new Error('Failed to create scratchpad');
		const created = await createResponse.json();
		if (!created?.id) throw new Error('Scratchpad id missing');
		scratchpadId = created.id;
		localStorage.setItem(scratchpadStorageKey, created.id);
		return created.id;
	}

	async function ensureScratchpadExists() {
		const noteId = await resolveScratchpadId();
		const response = await fetch(
			`/api/files/content?basePath=notes&path=${encodeURIComponent(noteId)}`
		);
		if (!response.ok) throw new Error('Missing scratchpad');
		const data = await response.json();
		const content = typeof data.content === 'string' ? data.content : '';
		return content;
	}

	async function loadScratchpad() {
		if (isLoading) return;
		isLoading = true;
		saveError = null;
		try {
			const content = await ensureScratchpadExists();
			lastSavedContent = content;
			if (editor) {
				isUpdatingContent = true;
				hasUserEdits = false;
				editor.commands.setContent(stripHeading(content) || '');
				setTimeout(() => {
					isUpdatingContent = false;
				}, 0);
			}
		} catch (error) {
			saveError = 'Failed to load scratchpad.';
		} finally {
			isLoading = false;
		}
	}

	function scheduleSave() {
		if (saveTimeout) clearTimeout(saveTimeout);
		saveTimeout = setTimeout(() => {
			saveScratchpad();
		}, 1200);
	}

	async function saveScratchpad() {
		if (!editor || isUpdatingContent) return;
		const markdown = editor.storage.markdown.getMarkdown();
		await saveScratchpadContent(markdown);
	}

	async function saveScratchpadContent(markdown: string) {
		const cleanedMarkdown = removeEmptyTaskItems(markdown);
		const content = withHeading(cleanedMarkdown);
		if (content === lastSavedContent) return;

		isSaving = true;
		saveError = null;
		try {
			const noteId = await resolveScratchpadId();
			const response = await fetch('/api/files/content', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					basePath: 'notes',
					path: noteId,
					content
				})
			});

			if (!response.ok) throw new Error('Failed to save scratchpad');
			lastSavedContent = content;
			hasUserEdits = false;
		} catch (error) {
			saveError = 'Failed to save scratchpad.';
		} finally {
			isSaving = false;
		}
	}

	function initEditor() {
		if (!editorElement || editor) return;
		editor = new Editor({
			element: editorElement,
			extensions: [StarterKit, TaskList, TaskItem.configure({ nested: true }), Markdown],
			content: '',
			editable: true,
			editorProps: {
				attributes: {
					class: 'tiptap scratchpad-editor'
				}
			},
			onUpdate: () => {
				if (isUpdatingContent) return;
				hasUserEdits = true;
				scheduleSave();
			}
		});
	}

	onDestroy(() => {
		if (saveTimeout) clearTimeout(saveTimeout);
		if (editor) editor.destroy();
	});

	$: if (isOpen && editorElement && !editor) {
		initEditor();
		loadScratchpad();
		isClosing = false;
	} else if (!isOpen && editor && !isClosing) {
		const currentEditor = editor;
		const markdown = currentEditor.storage.markdown.getMarkdown();
		if (saveTimeout) clearTimeout(saveTimeout);
		isClosing = true;
		(async () => {
			if (hasUserEdits) {
				await saveScratchpadContent(markdown);
			}
			if (!isOpen && editor === currentEditor) {
				currentEditor.destroy();
				editor = null;
			}
			isClosing = false;
		})();
	}
</script>

<Popover.Root bind:open={isOpen}>
	<Popover.Trigger class={buttonVariants({ variant: 'outline', size: 'icon' })} aria-label="Open scratchpad">
		<Pencil size={18} />
	</Popover.Trigger>
	<Popover.Content class="scratchpad-popover">
		<div class="scratchpad-header">
			<h2>✏️ Scratchpad</h2>
			{#if isSaving}
				<span class="status">Saving...</span>
			{:else if saveError}
				<span class="status error">{saveError}</span>
			{:else}
				<span class="status">Auto-save</span>
			{/if}
		</div>
		<div class="scratchpad-body">
			<div bind:this={editorElement} class="scratchpad-editor"></div>
			{#if isLoading}
				<div class="scratchpad-loading">Loading...</div>
			{/if}
		</div>
	</Popover.Content>
</Popover.Root>

<style>
	.scratchpad-popover {
		width: min(92vw, 840px);
		max-height: min(85vh, 720px);
		display: flex;
		flex-direction: column;
		gap: 0.75rem;
	}

	.scratchpad-header {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: 1rem;
		border-bottom: 1px solid var(--color-border);
		padding-bottom: 0.5rem;
	}

	.scratchpad-header h2 {
		margin: 0;
		font-size: 1.1rem;
		font-weight: 600;
		color: var(--color-foreground);
	}

	.status {
		font-size: 0.75rem;
		color: var(--color-muted-foreground);
	}

	.status.error {
		color: var(--color-destructive);
	}

	.scratchpad-body {
		flex: 1;
		overflow: hidden;
		position: relative;
	}

	.scratchpad-loading {
		position: absolute;
		inset: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		font-size: 0.875rem;
		color: var(--color-muted-foreground);
		background: color-mix(in oklab, var(--color-background) 85%, transparent);
	}

	:global(.scratchpad-editor) {
		min-height: 28rem;
		max-height: 60vh;
		overflow-y: auto;
		padding: 0.25rem 0.5rem 0.5rem 0;
		outline: none;
		color: var(--color-foreground);
	}

	:global(.scratchpad-editor p) {
		margin: 0.5em 0;
		line-height: 1.6;
	}

	:global(.scratchpad-editor ul),
	:global(.scratchpad-editor ol) {
		margin: 0.5em 0;
		padding-left: 1.5em;
	}

	:global(.scratchpad-editor li) {
		margin: 0;
	}

	:global(.scratchpad-editor li p) {
		margin: 0;
	}

	:global(.scratchpad-editor ul[data-type='taskList']) {
		list-style: none;
		padding-left: 0;
	}

	:global(.scratchpad-editor ul[data-type='taskList'] ul[data-type='taskList']) {
		margin-top: 0;
		margin-bottom: 0;
	}

	:global(.scratchpad-editor ul[data-type='taskList'] > li) {
		display: flex;
		align-items: flex-start;
		gap: 0.5em;
	}

	:global(.scratchpad-editor ul[data-type='taskList'] > li > label) {
		margin-top: 0.2em;
	}

	:global(.scratchpad-editor ul[data-type='taskList'] > li > div) {
		flex: 1;
	}

	:global(.scratchpad-editor ul[data-type='taskList'] > li > div > p) {
		margin: 0;
	}

	:global(.scratchpad-editor ul[data-type='taskList'] > li[data-checked='true'] > div) {
		color: var(--color-muted-foreground);
		text-decoration: line-through;
	}
</style>
