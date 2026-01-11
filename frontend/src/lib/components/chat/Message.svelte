<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import type { Message } from '$lib/types/chat';
	import { Badge } from '$lib/components/ui/badge';
	import { Button } from '$lib/components/ui/button';
	import { Tooltip, TooltipContent, TooltipTrigger } from '$lib/components/ui/tooltip';
	import { TOOLTIP_COPY } from '$lib/constants/tooltips';
	import { canShowTooltips } from '$lib/utils/tooltip';
	import { AlertTriangle, Check, Copy, Wrench } from 'lucide-svelte';
	import ChatMarkdown from './ChatMarkdown.svelte';
	import { logError } from '$lib/utils/errorHandling';

	export let message: Message;
	export let activeTool: {
		messageId: string;
		name: string;
		status: 'running' | 'success' | 'error';
		startedAt?: number;
	} | null = null;

	let copyTimeout: ReturnType<typeof setTimeout> | null = null;
	let isCopied = false;
	let tooltipsEnabled = false;

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
	onMount(() => {
		tooltipsEnabled = canShowTooltips();
	});

	function formatTime(date: Date): string {
		return new Date(date).toLocaleTimeString('en-US', {
			hour: '2-digit',
			minute: '2-digit',
			hour12: false
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
			logError('Failed to copy message content', error, { scope: 'chatMessage.copy' });
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
				<span class="streaming-indicator">
					<span class="streaming-dot">●</span>
					<span class="streaming-text">Working...</span>
				</span>
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
			<Tooltip disabled={!tooltipsEnabled}>
				<TooltipTrigger>
					{#snippet child({ props })}
						<Button
							size="icon"
							variant="ghost"
							class="h-6 w-6 opacity-0 group-hover:opacity-100 transition-opacity"
							{...props}
							onclick={(event) => {
								props.onclick?.(event);
								handleCopy(event);
							}}
							aria-label={isCopied ? 'Copied message' : 'Copy message'}
						>
							{#if isCopied}
								<Check size={14} />
							{:else}
								<Copy size={14} />
							{/if}
						</Button>
					{/snippet}
				</TooltipTrigger>
				<TooltipContent side="top">
					{isCopied ? TOOLTIP_COPY.copyMessage.success : TOOLTIP_COPY.copyMessage.default}
				</TooltipContent>
			</Tooltip>
		{/if}
	</div>

	{#if message.content}
		<ChatMarkdown content={message.content} />
	{/if}

	<div class="message-footer">
		<span class="timestamp">{formatTime(message.timestamp)}</span>
	</div>

	{#if message.error}
		<div
			class="mt-3 p-3 bg-destructive/10 border border-destructive rounded text-sm text-destructive"
		>
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

	.streaming-indicator {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		font-size: 0.75rem;
		color: var(--color-muted-foreground);
	}

	.streaming-dot {
		font-size: 0.85rem;
		animation: pulse 1.5s ease-in-out infinite;
	}

	.streaming-text {
		position: relative;
		background: linear-gradient(
			90deg,
			color-mix(in oklab, var(--color-muted-foreground) 35%, transparent) 0%,
			var(--color-muted-foreground) 50%,
			color-mix(in oklab, var(--color-muted-foreground) 35%, transparent) 100%
		);
		background-size: 200% 100%;
		-webkit-background-clip: text;
		background-clip: text;
		color: transparent;
		animation: shimmer 1.5s ease-in-out infinite;
	}

	@keyframes shimmer {
		0% {
			background-position: 200% 0;
		}
		100% {
			background-position: -200% 0;
		}
	}

	@keyframes pulse {
		0% {
			opacity: 0.35;
		}
		50% {
			opacity: 1;
		}
		100% {
			opacity: 0.35;
		}
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
