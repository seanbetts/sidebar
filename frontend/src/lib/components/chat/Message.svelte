<script lang="ts">
	import { onDestroy } from 'svelte';
	import type { Message } from '$lib/types/chat';
	import { Badge } from '$lib/components/ui/badge';
	import { Button } from '$lib/components/ui/button';
	import { Copy, Check } from 'lucide-svelte';
	import ChatMarkdown from './ChatMarkdown.svelte';
	import ToolCall from './ToolCall.svelte';

	export let message: Message;

	let copyTimeout: ReturnType<typeof setTimeout> | null = null;
	let isCopied = false;

	$: roleColor = message.role === 'user' ? 'bg-muted' : 'bg-card';
	$: roleName = message.role === 'user' ? 'You' : 'sideBar';

	function formatTime(date: Date): string {
		return new Date(date).toLocaleTimeString('en-US', {
			hour: 'numeric',
			minute: '2-digit'
		});
	}

	async function handleCopy() {
		if (!message.content) return;
		try {
			await navigator.clipboard.writeText(message.content);
			isCopied = true;
			if (copyTimeout) clearTimeout(copyTimeout);
			copyTimeout = setTimeout(() => {
				isCopied = false;
				copyTimeout = null;
			}, 1500);
		} catch (error) {
			console.error('Failed to copy message content:', error);
		}
	}

	onDestroy(() => {
		if (copyTimeout) clearTimeout(copyTimeout);
	});
</script>

<div class="group p-4 {roleColor} rounded-lg mb-4 border">
	<div class="flex items-center justify-between gap-2 mb-2">
		<div class="flex items-center gap-2">
			<Badge variant={message.role === 'user' ? 'default' : 'outline'}>{roleName}</Badge>
			<span class="text-xs text-muted-foreground">{formatTime(message.timestamp)}</span>
			{#if message.status === 'streaming'}
				<span class="text-xs animate-pulse">●</span>
			{/if}
		</div>
		{#if message.content}
			<Button
				size="icon"
				variant="ghost"
				class="h-6 w-6 opacity-0 group-hover:opacity-100 transition-opacity"
				onclick={handleCopy}
				aria-label={isCopied ? 'Copied message' : 'Copy message'}
				title={isCopied ? 'Copied' : 'Copy message'}
			>
				{#if isCopied}
					<Check size={14} />
				{:else}
					<Copy size={14} />
				{/if}
			</Button>
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
