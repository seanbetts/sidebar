<script lang="ts">
	import { onMount, afterUpdate, tick } from 'svelte';
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

	// Auto-scroll when messages update
	afterUpdate(() => {
		if (shouldAutoScroll) {
			scrollToBottom();
		}
	});

	onMount(async () => {
		await tick();
		scrollToBottom();
	});

	$: if (messages.length !== lastMessageCount) {
		lastMessageCount = messages.length;
		shouldAutoScroll = true;
		tick().then(scrollToBottom);
	}
</script>

<div bind:this={containerElement} onscroll={handleScroll} class="message-list">
	{#if messages.length === 0}
		<div class="h-full"></div>
	{:else}
		{#each messages as message (message.id)}
			<Message {message} {activeTool} />
		{/each}
	{/if}
</div>

<style>
	.message-list {
		flex: 1;
		min-height: 0;
		overflow-y: auto;
		overflow-x: hidden;
		padding: 1rem;
		display: flex;
		flex-direction: column;
		gap: 1rem;
		-webkit-overflow-scrolling: touch; /* Smooth scrolling on iOS */
	}
</style>
