<script lang="ts">
	import { onDestroy, onMount, tick } from 'svelte';
	import type { Message as MessageType } from '$lib/types/chat';
	import Message from './Message.svelte';

	export let messages: MessageType[];
	export let conversationId: string | null = null;
	export let activeTool: {
		messageId: string;
		name: string;
		status: 'running' | 'success' | 'error';
		startedAt?: number;
	} | null = null;

	let containerElement: HTMLDivElement;
	let messagesContainerElement: HTMLDivElement;
	let shouldAutoScroll = true;
	let lastMessageCount = 0;
	let lastConversationId: string | null | undefined;
	let scrollFrameId: number | null = null;
	let resizeObserver: ResizeObserver | null = null;

	function scrollToBottom(force = false) {
		if (containerElement && (force || shouldAutoScroll)) {
			containerElement.scrollTop = containerElement.scrollHeight;
		}
	}

	function scheduleScrollToBottom(force = false) {
		if (!containerElement || (!force && !shouldAutoScroll)) return;
		tick().then(() => {
			if (scrollFrameId !== null) {
				cancelAnimationFrame(scrollFrameId);
			}
			scrollFrameId = requestAnimationFrame(() => {
				scrollFrameId = null;
				scrollToBottom(force);
			});
		});
	}

	function isNearBottom() {
		if (!containerElement) return true;
		return (
			containerElement.scrollHeight - containerElement.scrollTop - containerElement.clientHeight <
			100
		);
	}

	function handleScroll() {
		if (!containerElement) return;
		shouldAutoScroll = isNearBottom();
	}

	$: if (messages.length !== lastMessageCount) {
		lastMessageCount = messages.length;
		shouldAutoScroll = true;
		scheduleScrollToBottom(true);
	}

	$: if (conversationId !== lastConversationId) {
		lastConversationId = conversationId;
		shouldAutoScroll = true;
		scheduleScrollToBottom(true);
	}

	onMount(() => {
		const handleViewportResize = () => {
			if (shouldAutoScroll || isNearBottom()) {
				shouldAutoScroll = true;
				scheduleScrollToBottom(true);
			}
		};

		window.addEventListener('resize', handleViewportResize);
		window.visualViewport?.addEventListener('resize', handleViewportResize);

		if (typeof ResizeObserver !== 'undefined' && messagesContainerElement) {
			resizeObserver = new ResizeObserver(() => {
				if (shouldAutoScroll || isNearBottom()) {
					shouldAutoScroll = true;
					scheduleScrollToBottom(true);
				}
			});
			resizeObserver.observe(messagesContainerElement);
		}

		scheduleScrollToBottom(true);

		return () => {
			window.removeEventListener('resize', handleViewportResize);
			window.visualViewport?.removeEventListener('resize', handleViewportResize);
			resizeObserver?.disconnect();
			resizeObserver = null;
		};
	});

	onDestroy(() => {
		if (scrollFrameId !== null) {
			cancelAnimationFrame(scrollFrameId);
			scrollFrameId = null;
		}
	});
</script>

<div bind:this={containerElement} onscroll={handleScroll} class="message-list">
	<div bind:this={messagesContainerElement} class="messages-container">
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
	.message-list {
		flex: 1;
		min-height: 0;
		overflow-y: auto;
		overflow-x: hidden;
		padding: 1rem;
		-webkit-overflow-scrolling: touch; /* Smooth scrolling on iOS */
	}

	.messages-container {
		max-width: 800px;
		margin: 0 auto;
		display: flex;
		flex-direction: column;
		gap: 1rem;
	}
</style>
