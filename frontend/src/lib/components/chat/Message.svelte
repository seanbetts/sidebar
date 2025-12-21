<script lang="ts">
	import type { Message } from '$lib/types/chat';
	import ToolCall from './ToolCall.svelte';

	export let message: Message;

	$: roleColor = message.role === 'user' ? 'bg-blue-50' : 'bg-gray-50';
	$: roleName = message.role === 'user' ? 'You' : 'Agent Smith';

	function formatTime(date: Date): string {
		return new Date(date).toLocaleTimeString('en-US', {
			hour: 'numeric',
			minute: '2-digit'
		});
	}
</script>

<div class="p-4 {roleColor} rounded-lg mb-4">
	<div class="flex items-center gap-2 mb-2">
		<span class="font-medium text-sm">{roleName}</span>
		<span class="text-xs text-gray-500">{formatTime(message.timestamp)}</span>
		{#if message.status === 'streaming'}
			<span class="text-xs text-blue-500 animate-pulse">●</span>
		{/if}
	</div>

	{#if message.content}
		<div class="prose prose-sm max-w-none whitespace-pre-wrap">
			{message.content}
		</div>
	{/if}

	{#if message.toolCalls && message.toolCalls.length > 0}
		<div class="mt-3 space-y-2">
			{#each message.toolCalls as toolCall (toolCall.id)}
				<ToolCall {toolCall} />
			{/each}
		</div>
	{/if}

	{#if message.error}
		<div class="mt-3 p-3 bg-red-100 border border-red-300 rounded text-sm text-red-700">
			<strong>Error:</strong>
			{message.error}
		</div>
	{/if}
</div>
