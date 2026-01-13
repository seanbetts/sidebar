<script lang="ts">
	import { tick } from 'svelte';
	import type { Message as MessageType } from '$lib/types/chat';
	import Message from './Message.svelte';

	export let messages: MessageType[];
	export let activeTool: {
		messageId: string;
		name: string;
		status: 'running' | 'success' | 'error';
		startedAt?: number;
	} | null = null;

	let containerElement: HTMLDivElement;
	let shouldAutoScroll = true;
	let lastMessageCount = 0;

	function scrollToBottom() {
		if (containerElement && shouldAutoScroll) {
			containerElement.scrollTop = containerElement.scrollHeight;
		}
	}

	function handleScroll() {
		if (!containerElement) return;

		// Check if user is near bottom (within 100px)
		const isNearBottom =
			containerElement.scrollHeight - containerElement.scrollTop - containerElement.clientHeight <
			100;

		shouldAutoScroll = isNearBottom;
	}

	$: if (messages.length !== lastMessageCount) {
		lastMessageCount = messages.length;
		shouldAutoScroll = true;
		tick().then(scrollToBottom);
	}
</script>

<div bind:this={containerElement} onscroll={handleScroll} class="flex-1 overflow-y-auto p-4">
	<div class="messages-container">
		{#if messages.length === 0}
			<div class="h-full"></div>
		{:else}
			{#each messages as message (message.id)}
				<Message {message} {activeTool} />
			{/each}
		{/if}
	</div>
</div>

<style>
	.messages-container {
		max-width: 800px;
		margin: 0 auto;
		display: flex;
		flex-direction: column;
		gap: 1rem;
	}
</style>
