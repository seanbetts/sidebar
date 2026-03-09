<script lang="ts">
	import { onMount } from 'svelte';
	import type { Editor } from '@tiptap/core';
	import { createMarkdownExtensions, loadTiptapModules } from '$lib/components/editor/tiptapLoader';

	export let content: string;

	let editorElement: HTMLDivElement;
	let editor: Editor | null = null;

	onMount(() => {
		let isDisposed = false;

		void (async () => {
			const modules = await loadTiptapModules();
			if (isDisposed || !editorElement) {
				return;
			}

			editor = new modules.Editor({
				element: editorElement,
				extensions: createMarkdownExtensions(modules),
				content: '',
				editable: false,
				editorProps: {
					attributes: {
						class: 'tiptap chat-markdown prose prose-sm max-w-none'
					}
				}
			});
		})();

		return () => {
			isDisposed = true;
			editor?.destroy();
			editor = null;
		};
	});

	$: if (editor) {
		editor.commands.setContent(content || '');
	}
</script>

<div bind:this={editorElement}></div>

<style>
	:global(.chat-markdown [contenteditable='false']:focus) {
		outline: none;
	}
</style>
