<script lang="ts">
	import { onDestroy } from 'svelte';
	import type { Message } from '$lib/types/chat';
	import { Badge } from '$lib/components/ui/badge';
	import { Button } from '$lib/components/ui/button';
	import { AlertTriangle, Check, Copy, Wrench } from 'lucide-svelte';
	import ChatMarkdown from './ChatMarkdown.svelte';

	export let message: Message;
	export let activeTool: {
		messageId: string;
		name: string;
		status: 'running' | 'success' | 'error';
		startedAt?: number;
	} | null = null;

	let copyTimeout: ReturnType<typeof setTimeout> | null = null;
	let isCopied = false;

	$: roleColor = message.role === 'user' ? 'bg-muted' : 'bg-card';
	$: roleName = message.role === 'user' ? 'You' : 'sideBar';
	$: isToolActive = activeTool?.messageId === message.id;
	$: toolLabel = (() => {
		const name = activeTool?.name || 'a tool';
		if (activeTool?.status === 'success') {
			return `Used ${name}`;
		}
		if (activeTool?.status === 'error') {
			return `Failed to use ${name}`;
		}
		return `Using ${name}`;
	})();

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
			{#if message.status === 'streaming'}
				<span class="text-xs animate-pulse">●</span>
			{/if}
			{#if isToolActive}
				<span class="server-tool-indicator">
					{#if activeTool?.status === 'running'}
						<Wrench size={12} />
					{:else if activeTool?.status === 'success'}
						<Check size={12} />
					{:else if activeTool?.status === 'error'}
						<AlertTriangle size={12} />
					{/if}
					<span>{toolLabel}</span>
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
		<ChatMarkdown content={message.content} />
	{/if}

	<div class="message-footer">
		<span class="timestamp">{formatTime(message.timestamp)}</span>
	</div>

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

	.message-footer {
		display: flex;
		justify-content: flex-end;
		margin-top: 0.5rem;
	}

	.timestamp {
		font-size: 0.7rem;
		color: var(--color-muted-foreground);
	}
</style>
