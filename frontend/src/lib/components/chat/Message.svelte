<script lang="ts">
	import { onDestroy } from 'svelte';
	import type { Message } from '$lib/types/chat';
	import { Badge } from '$lib/components/ui/badge';
	import { Button } from '$lib/components/ui/button';
	import { Copy, Check } from 'lucide-svelte';
	import ChatMarkdown from './ChatMarkdown.svelte';
	import ToolCall from './ToolCall.svelte';

	export let message: Message;
	export let serverTool: { messageId: string; name: string; query?: string } | null = null;

	let copyTimeout: ReturnType<typeof setTimeout> | null = null;
	let isCopied = false;

	$: roleColor = message.role === 'user' ? 'bg-muted' : 'bg-card';
	$: roleName = message.role === 'user' ? 'You' : 'sideBar';
	$: isServerToolActive = serverTool?.messageId === message.id;
	$: serverToolLabel =
		serverTool?.name === 'web_search' ? 'Searching the web...' : 'Running a server tool...';

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
			{#if isServerToolActive}
				<span class="server-tool-indicator">
					<span class="server-tool-dot"></span>
					<span>{serverToolLabel}</span>
				</span>
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

<style>
	.server-tool-indicator {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		font-size: 0.75rem;
		color: var(--color-muted-foreground);
	}

	.server-tool-dot {
		width: 0.45rem;
		height: 0.45rem;
		border-radius: 999px;
		background: var(--color-muted-foreground);
		animation: pulse 1.5s ease-in-out infinite;
	}

	@keyframes pulse {
		0% {
			opacity: 0.3;
			transform: scale(0.9);
		}
		50% {
			opacity: 1;
			transform: scale(1);
		}
		100% {
			opacity: 0.3;
			transform: scale(0.9);
		}
	}
</style>
