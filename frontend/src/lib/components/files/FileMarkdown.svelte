<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import { Editor } from '@tiptap/core';
	import StarterKit from '@tiptap/starter-kit';
	import { ImageGallery } from '$lib/components/editor/ImageGallery';
	import { ImageWithCaption } from '$lib/components/editor/ImageWithCaption';
	import { TaskList, TaskItem } from '@tiptap/extension-list';
	import { TableKit } from '@tiptap/extension-table';
	import { Markdown } from 'tiptap-markdown';

	export let content: string;

	let editorElement: HTMLDivElement;
	let editor: Editor | null = null;

	onMount(() => {
		editor = new Editor({
			element: editorElement,
			extensions: [
				StarterKit,
				ImageGallery,
				ImageWithCaption.configure({ inline: false, allowBase64: true }),
				TaskList,
				TaskItem.configure({ nested: true }),
				TableKit,
				Markdown.configure({ html: true })
			],
			content: '',
			editable: false,
			editorProps: {
				attributes: {
					class: 'tiptap file-markdown prose prose-sm max-w-none'
				}
			}
		});
	});

	onDestroy(() => {
		editor?.destroy();
	});

	$: if (editor) {
		editor.commands.setContent(content || '');
	}
</script>

<div bind:this={editorElement}></div>

<style>
	:global(.file-markdown [contenteditable='false']:focus) {
		outline: none;
	}
</style>
