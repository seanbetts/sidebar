<script lang="ts">
	import MarkdownEditor from '$lib/components/editor/MarkdownEditor.svelte';
	import ChatSidebar from '$lib/components/chat/ChatSidebar.svelte';
	import ResizeHandle from '$lib/components/layout/ResizeHandle.svelte';
	import WebsitesViewer from '$lib/components/websites/WebsitesViewer.svelte';
	import { layoutStore } from '$lib/stores/layout';
	import { websitesStore } from '$lib/stores/websites';

	let sidebarRef: HTMLElement;

	$: isChatFocused = $layoutStore.mode === 'chat-focused';
	$: sidebarWidth = isChatFocused
		? $layoutStore.workspaceSidebarWidth
		: $layoutStore.chatSidebarWidth;

	function handleResize(width: number) {
		if (isChatFocused) {
			layoutStore.setWorkspaceSidebarWidth(width);
		} else {
			layoutStore.setChatSidebarWidth(width);
		}
	}
</script>

<div class="page-container" class:chat-focused={isChatFocused}>
	<div class="panel main-panel">
		{#if isChatFocused}
			<ChatSidebar />
		{:else}
			{#if $websitesStore.active}
				<WebsitesViewer />
			{:else}
				<MarkdownEditor />
			{/if}
		{/if}
	</div>

	<ResizeHandle containerRef={sidebarRef} side="right" onResize={handleResize} />

	<div
		class="panel sidebar-panel"
		bind:this={sidebarRef}
		style:width={`${sidebarWidth}px`}
	>
		{#if isChatFocused}
			{#if $websitesStore.active}
				<WebsitesViewer />
			{:else}
				<MarkdownEditor />
			{/if}
		{:else}
			<ChatSidebar />
		{/if}
	</div>
</div>

<style>
	.page-container {
		display: flex;
		height: 100%;
		width: 100%;
		overflow: hidden;
		min-height: 0;
	}

	.panel {
		overflow: hidden;
		min-height: 0;
	}

	.main-panel {
		flex: 1;
	}

	.sidebar-panel {
		flex-shrink: 0;
		border-left: 1px solid var(--color-border);
		transition: width 0.15s ease;
	}

	@media (max-width: 900px) {
		.sidebar-panel {
			width: 340px;
		}

		:global(.resize-handle) {
			display: none;
		}
	}
</style>
