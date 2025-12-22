<script lang="ts">
	import MarkdownEditor from '$lib/components/editor/MarkdownEditor.svelte';
	import ChatSidebar from '$lib/components/chat/ChatSidebar.svelte';
</script>

<div class="page-container">
	<div class="main-area">
		<MarkdownEditor />
	</div>

	<ChatSidebar />
</div>

<style>
	.page-container {
		display: flex;
		height: 100vh;
		width: 100%;
		overflow: hidden;
	}

	.main-area {
		flex: 1;
		overflow: hidden;
	}
</style>
