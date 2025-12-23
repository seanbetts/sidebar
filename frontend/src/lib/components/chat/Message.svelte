<script lang="ts">
	import type { Message } from '$lib/types/chat';
	import { Badge } from '$lib/components/ui/badge';
	import ChatMarkdown from './ChatMarkdown.svelte';
	import ToolCall from './ToolCall.svelte';

	export let message: Message;

	$: roleColor = message.role === 'user' ? 'bg-muted' : 'bg-card';
	$: roleName = message.role === 'user' ? 'You' : 'Agent Smith';

	function formatTime(date: Date): string {
		return new Date(date).toLocaleTimeString('en-US', {
			hour: 'numeric',
			minute: '2-digit'
		});
	}
</script>

<div class="p-4 {roleColor} rounded-lg mb-4 border">
	<div class="flex items-center gap-2 mb-2">
		<Badge variant={message.role === 'user' ? 'default' : 'outline'}>{roleName}</Badge>
		<span class="text-xs text-muted-foreground">{formatTime(message.timestamp)}</span>
		{#if message.status === 'streaming'}
			<span class="text-xs animate-pulse">●</span>
		{/if}
	</div>

	{#if message.content}
		{#if message.status === 'streaming'}
			<div class="text-sm whitespace-pre-wrap text-foreground">
				{message.content}
			</div>
		{:else}
			<ChatMarkdown content={message.content} />
		{/if}
	{/if}

	{#if message.toolCalls && message.toolCalls.length > 0}
		<div class="mt-3 space-y-2">
			{#each message.toolCalls as toolCall (toolCall.id)}
				<ToolCall {toolCall} />
			{/each}
		</div>
	{/if}

	{#if message.error}
		<div class="mt-3 p-3 bg-destructive/10 border border-destructive rounded text-sm text-destructive">
			<strong>Error:</strong>
			{message.error}
		</div>
	{/if}
</div>
