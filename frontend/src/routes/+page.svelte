<script lang="ts">
	import MarkdownEditor from '$lib/components/editor/MarkdownEditor.svelte';
	import ChatSidebar from '$lib/components/chat/ChatSidebar.svelte';
	import WebsitesViewer from '$lib/components/websites/WebsitesViewer.svelte';
	import { websitesStore } from '$lib/stores/websites';
</script>

<div class="page-container">
	<div class="main-area">
		{#if $websitesStore.active}
			<WebsitesViewer />
		{:else}
			<MarkdownEditor />
		{/if}
	</div>

	<ChatSidebar />
</div>

<style>
	.page-container {
		display: flex;
		height: 100%;
		width: 100%;
		overflow: hidden;
		min-height: 0;
	}

	.main-area {
		flex: 1;
		overflow: hidden;
		min-height: 0;
	}
</style>
