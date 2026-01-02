<script lang="ts">
	import { onDestroy, tick } from 'svelte';
	import { scratchpadStore } from '$lib/stores/scratchpad';
	import { Editor } from '@tiptap/core';
	import StarterKit from '@tiptap/starter-kit';
	import { Image } from '@tiptap/extension-image';
	import { TaskList, TaskItem } from '@tiptap/extension-list';
	import { TableKit } from '@tiptap/extension-table';
	import { Markdown } from 'tiptap-markdown';
	import { TextSelection } from '@tiptap/pm/state';
import { SquarePen } from 'lucide-svelte';
	import { buttonVariants } from '$lib/components/ui/button/index.js';
	import * as Popover from '$lib/components/ui/popover/index.js';
	import ScratchpadHeader from '$lib/components/scratchpad/ScratchpadHeader.svelte';
	import {
		removeEmptyTaskItems,
		stripHeading,
		withHeading
	} from '$lib/utils/scratchpad';

	let editorElement: HTMLDivElement;
	let editor: Editor | null = null;
	let isOpen = false;
	let isLoading = false;
	let isSaving = false;
	let saveError: string | null = null;
	let lastSavedContent = '';

	// Flag to prevent infinite loops:
	// When we programmatically update the editor (e.g., loading scratchpad),
	// we don't want that to trigger onUpdate which would mark it as dirty
	let isUpdatingContent = false;
	let saveTimeout: ReturnType<typeof setTimeout> | undefined;
	let isClosing = false;
	let hasUserEdits = false;

	function applyScratchpadContent(content: string) {
		lastSavedContent = content;
		if (!editor) return;
		const newContent = stripHeading(content) || '';
		const currentEditorContent = editor.storage.markdown.getMarkdown();

		if (currentEditorContent === newContent) {
			return;
		}

		try {
			isUpdatingContent = true;
			hasUserEdits = false;
			const currentPosition = editor.state.selection.anchor;
			editor.commands.setContent(newContent);
			tick().then(() =>
				requestAnimationFrame(() => {
					if (editor) {
						const maxPosition = editor.state.doc.content.size;
						const safePosition = Math.min(currentPosition, maxPosition);
						const selection = TextSelection.near(editor.state.doc.resolve(safePosition));
						editor.view.dispatch(editor.state.tr.setSelection(selection));
					}
				})
			);
		} catch (error) {
			console.error('Failed to update scratchpad content:', error);
		} finally {
			isUpdatingContent = false;
		}
	}


	async function ensureScratchpadExists() {
		const response = await fetch('/api/scratchpad');
		if (!response.ok) throw new Error('Missing scratchpad');
		const data = await response.json();
		const content = typeof data.content === 'string' ? data.content : '';
		return content;
	}

	async function loadScratchpad() {
		if (isLoading) return;
		isLoading = true;
		saveError = null;
		const cachedContent = scratchpadStore.getCachedContent();
		if (cachedContent) {
			applyScratchpadContent(cachedContent);
			isLoading = false;
		}
		try {
			const content = await ensureScratchpadExists();
			applyScratchpadContent(content);
			scratchpadStore.setCachedContent(content);
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
		const body = stripHeading(cleanedMarkdown).trim();
		const content = withHeading(cleanedMarkdown);
		if (content === lastSavedContent) return;

		isSaving = true;
		saveError = null;
		try {
			const response = await fetch('/api/scratchpad', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					content,
					mode: 'replace'
				})
			});

			if (!response.ok) throw new Error('Failed to save scratchpad');
			lastSavedContent = content;
			hasUserEdits = false;
			scratchpadStore.setCachedContent(content);
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
			extensions: [
				StarterKit,
				Image.configure({ inline: false, allowBase64: true }),
				TaskList,
				TaskItem.configure({ nested: true }),
				TableKit,
				Markdown
			],
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

	const unsubscribeScratchpad = scratchpadStore.subscribe(() => {
		if (isOpen && !isLoading) {
			loadScratchpad();
		}
	});

	onDestroy(() => {
		// Cleanup all timers and subscriptions
		if (saveTimeout) clearTimeout(saveTimeout);
		unsubscribeScratchpad();
		if (editor) {
			editor.destroy();
			editor = null;  // Set to null to prevent double destruction
		}
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
			// Only destroy if editor hasn't been destroyed already and popover is still closed
			if (!isOpen && editor === currentEditor && editor !== null) {
				currentEditor.destroy();
				editor = null;
			}
			isClosing = false;
		})();
	}
</script>

<Popover.Root bind:open={isOpen}>
	<Popover.Trigger class={buttonVariants({ variant: 'outline', size: 'icon' })} aria-label="Open scratchpad">
		<SquarePen size={18} />
	</Popover.Trigger>
	<Popover.Content class="w-[95vw] max-w-[840px] p-0" align="end" sideOffset={8}>
		<div class="scratchpad-popover">
			<ScratchpadHeader {isSaving} {saveError} />
			<div class="scratchpad-body">
				<div bind:this={editorElement} class="scratchpad-editor"></div>
				{#if isLoading}
					<div class="scratchpad-loading">Loading...</div>
				{/if}
			</div>
		</div>
	</Popover.Content>
</Popover.Root>

<style>
	.scratchpad-popover {
		width: 100%;
		max-width: 100%;
		margin-right: 1rem;
		max-height: min(85vh, 720px);
		height: min(85vh, 720px);
		display: flex;
		flex-direction: column;
		gap: 0.75rem;
		overflow: hidden;
		padding: 1rem 0.5rem 1rem 1rem;
	}


	.scratchpad-body {
		flex: 1;
		display: flex;
		min-height: 0;
		overflow: hidden;
		position: relative;
	}

	:global(.scratchpad-header) {
		min-width: 0;
	}

	:global(.scratchpad-header .status) {
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
		max-width: 45%;
		text-align: right;
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
		flex: 1;
		min-height: 0;
		height: 100%;
		overflow-y: auto;
		padding: 0.25rem 0 0.5rem 0;
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

	:global(.scratchpad-editor table) {
		width: 100%;
		border-collapse: collapse;
		margin: 1em 0;
		font-size: 0.95em;
	}

	:global(.scratchpad-editor th),
	:global(.scratchpad-editor td) {
		border: 1px solid var(--color-border);
		padding: 0em 0.75em;
		text-align: left;
		vertical-align: top;
	}

	:global(.scratchpad-editor thead th) {
		background-color: var(--color-muted);
		color: var(--color-foreground);
		font-weight: 600;
	}

	:global(.scratchpad-editor tbody tr:nth-child(even)) {
		background-color: color-mix(in oklab, var(--color-muted) 40%, transparent);
	}

	:global(.scratchpad-editor hr) {
		border: none;
		border-top: 1px solid var(--color-border);
		margin: 1.25rem 0;
	}
</style>
