<script lang="ts">
	import { onMount, afterUpdate } from 'svelte';
	import type { Message as MessageType } from '$lib/types/chat';
	import Message from './Message.svelte';

	export let messages: MessageType[];
	export let serverTool: { messageId: string; name: string; query?: string } | null = null;

	let containerElement: HTMLDivElement;
	let shouldAutoScroll = true;

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
		scrollToBottom();
	});

	onMount(() => {
		scrollToBottom();
	});
</script>

<div
	bind:this={containerElement}
	onscroll={handleScroll}
	class="flex-1 overflow-y-auto p-4 space-y-4"
>
	{#if messages.length === 0}
		<div class="flex items-center justify-center h-full text-muted-foreground">
			<div class="text-center">
				<p class="text-xl mb-2 font-semibold">Welcome to sideBar</p>
				<p class="text-sm">Start a conversation by typing a message below</p>
			</div>
		</div>
	{:else}
		{#each messages as message (message.id)}
			<Message {message} {serverTool} />
		{/each}
	{/if}
</div>
