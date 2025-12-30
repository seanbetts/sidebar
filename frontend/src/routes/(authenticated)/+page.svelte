<script lang="ts">
	import { onMount } from 'svelte';
	import MarkdownEditor from '$lib/components/editor/MarkdownEditor.svelte';
	import ChatSidebar from '$lib/components/chat/ChatSidebar.svelte';
	import ResizeHandle from '$lib/components/layout/ResizeHandle.svelte';
	import WebsitesViewer from '$lib/components/websites/WebsitesViewer.svelte';
	import { layoutStore } from '$lib/stores/layout';
	import { websitesStore } from '$lib/stores/websites';

	let sidebarRef: HTMLElement;
	let pageContainerRef: HTMLElement;
	let isInitialLoad = true;

	$: isChatFocused = $layoutStore.mode === 'chat-focused';
	$: sidebarRatio = $layoutStore.sidebarRatio;
	$: containerWidth = pageContainerRef?.getBoundingClientRect().width ?? 0;
	$: minSidebarPx = isChatFocused ? 480 : 320;
	$: maxRatio = 0.5;
	$: minRatio = containerWidth ? Math.min(maxRatio, minSidebarPx / containerWidth) : 0;
	$: effectiveRatio = containerWidth
		? Math.min(maxRatio, Math.max(minRatio, sidebarRatio))
		: Math.min(maxRatio, sidebarRatio);
	$: sidebarWidth = containerWidth
		? `${(effectiveRatio * 100).toFixed(2)}%`
		: 'var(--sidebar-width, 38%)';

	const defaultChatWidth = 550;
	const defaultContainerWidth = 1200;
	const snapPoints = [0.33, 0.4, 0.5];

	onMount(() => {
		requestAnimationFrame(() => {
			requestAnimationFrame(() => {
				isInitialLoad = false;
			});
		});
	});

	function handleResize(width: number) {
		if (!containerWidth) return;
		const maxRatio = 0.5;
		const minRatio = Math.min(maxRatio, minSidebarPx / containerWidth);
		let ratio = Math.min(maxRatio, Math.max(minRatio, width / containerWidth));
		const snapDistance = 0.02;
		for (const point of snapPoints) {
			if (Math.abs(ratio - point) <= snapDistance) {
				ratio = point;
				break;
			}
		}
		layoutStore.setSidebarRatio(ratio);
	}

	function handleReset() {
		if (!containerWidth) return;
		const maxRatio = 0.5;
		const defaultSidebarRatio = Math.min(maxRatio, defaultChatWidth / containerWidth);
		const currentSidebarRatio = effectiveRatio;
		const nextSidebarRatio =
			Math.abs(currentSidebarRatio - maxRatio) < 0.01 ? defaultSidebarRatio : maxRatio;
		layoutStore.setSidebarRatio(nextSidebarRatio);
	}
</script>

<div class="page-container" class:chat-focused={isChatFocused} bind:this={pageContainerRef}>
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

	<ResizeHandle
		containerRef={sidebarRef}
		side="right"
		onResize={handleResize}
		onReset={handleReset}
	/>

	<div
		class="panel sidebar-panel"
		class:no-transition={isInitialLoad}
		bind:this={sidebarRef}
		style:width={sidebarWidth}
		style:min-width={`${minSidebarPx}px`}
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
		--panel-header-offset: 56px;
	}

	.panel {
		overflow: hidden;
		min-height: 0;
		position: relative;
		z-index: 1;
	}

	.main-panel {
		flex: 1;
	}

	.sidebar-panel {
		flex-shrink: 0;
		transition: width 0.15s ease;
		background-color: var(--color-background);
	}

	.sidebar-panel.no-transition {
		transition: none;
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
