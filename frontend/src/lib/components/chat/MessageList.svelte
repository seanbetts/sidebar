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

<div
	bind:this={containerElement}
	onscroll={handleScroll}
	class="flex-1 overflow-y-auto p-4 space-y-4"
>
	{#if messages.length === 0}
		<div class="flex items-center justify-center h-full text-muted-foreground">
			<div class="text-center">
				<img class="welcome-logo" src="/images/logo.svg" alt="sideBar" />
				<p class="text-xl mb-2 font-semibold">Welcome to sideBar</p>
				<p class="text-sm">Send a message to get started</p>
			</div>
		</div>
	{:else}
		{#each messages as message (message.id)}
			<Message {message} {activeTool} />
		{/each}
	{/if}
</div>

<style>
	.welcome-logo {
		height: 4rem;
		width: auto;
		margin: 0 auto 0.75rem;
		opacity: 0.7;
	}

	:global(.dark) .welcome-logo {
		filter: invert(1);
	}
</style>
