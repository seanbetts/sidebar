<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import { chatStore } from '$lib/stores/chat';
	import { Button } from '$lib/components/ui/button';
	import { Separator } from '$lib/components/ui/separator';
	import MessageList from './MessageList.svelte';
	import ChatInput from './ChatInput.svelte';
	import { toast } from 'svelte-sonner';
	import { get } from 'svelte/store';
	import { websitesStore } from '$lib/stores/websites';
	import { editorStore } from '$lib/stores/editor';
	import { ingestionViewerStore } from '$lib/stores/ingestion-viewer';
	import { ingestionStore } from '$lib/stores/ingestion';
	import { conversationListStore } from '$lib/stores/conversations';
	import { ingestionAPI } from '$lib/services/api';
	import {
		AlertTriangle,
		CheckCircle2,
		Loader2,
		MessageSquare,
		Plus,
		RotateCcw,
		Trash2,
		X
	} from 'lucide-svelte';
	import { getCachedData } from '$lib/utils/cache';
	import { dispatchCacheEvent } from '$lib/utils/cacheEvents';
	import { getUserFriendlyError, useChatSSE } from '$lib/composables/useChatSSE';
	import { logError } from '$lib/utils/errorHandling';
	import { Tooltip, TooltipContent, TooltipTrigger } from '$lib/components/ui/tooltip';
	import { TOOLTIP_COPY } from '$lib/constants/tooltips';
	import { canShowTooltips } from '$lib/utils/tooltip';

	const chatSse = useChatSSE();
	let attachments: Array<{
		id: string;
		fileId?: string;
		file?: File;
		name: string;
		status: string;
		stage?: string | null;
	}> = [];
	let attachmentPolls = new Map<string, ReturnType<typeof setTimeout>>();
	let isMounted = true;
	let previousConversationId: string | null = null;
	let tooltipsEnabled = false;

	onMount(() => {
		tooltipsEnabled = canShowTooltips();
		void restoreLastConversation();
	});

	onDestroy(() => {
		isMounted = false;
		attachmentPolls.forEach((timeoutId) => clearTimeout(timeoutId));
		attachmentPolls.clear();
		// Clean up SSE connection when component unmounts
		chatSse.disconnect();
		chatStore.cleanup?.();
	});

	async function restoreLastConversation() {
		if (get(chatStore).conversationId) return;
		try {
			await conversationListStore.load();
			const availableIds = get(conversationListStore).conversations.map(
				(conversation) => conversation.id
			);
			await chatStore.restoreLastConversation(availableIds);
		} catch (error) {
			logError('Failed to restore last conversation', error, {
				scope: 'ChatWindow.restoreLastConversation'
			});
		}
	}

	async function handleSend(message: string) {
		const pendingAttachments = attachments.filter((item) => item.status !== 'ready');
		if (pendingAttachments.length > 0) {
			toast.error('Files are still processing. Please wait before sending.');
			return;
		}

		// Add user message and start streaming assistant response
		const { assistantMessageId, userMessageId } = await chatStore.sendMessage(message);
		const { conversationId } = get(chatStore);
		const attachmentsForMessage = attachments
			.filter(
				(item): item is typeof item & { fileId: string } =>
					item.status === 'ready' && Boolean(item.fileId)
			)
			.map((item) => ({
				file_id: item.fileId,
				filename: item.name
			}));
		attachments = [];

		try {
			// Connect to SSE stream
			const editorState = get(editorStore);
			const websiteState = get(websitesStore);
			const fileState = get(ingestionViewerStore);
			const openContext: {
				note?: { id: string; title: string; path: string | null; content: string };
				website?: { id: string; title: string; url: string; domain: string; content: string };
				file?: { id: string; filename: string; mime?: string | null; category?: string | null };
			} = {};

			if (editorState.currentNoteId) {
				openContext.note = {
					id: editorState.currentNoteId,
					title: editorState.currentNoteName || 'Untitled note',
					path: editorState.currentNotePath,
					content: editorState.content || ''
				};
			}

			if (websiteState.active) {
				openContext.website = {
					id: websiteState.active.id,
					title: websiteState.active.title,
					url: websiteState.active.url_full || websiteState.active.url,
					domain: websiteState.active.domain,
					content: websiteState.active.content || ''
				};
			}

			if (fileState.active) {
				openContext.file = {
					id: fileState.active.file.id,
					filename: fileState.active.file.filename_original,
					mime: fileState.active.file.mime_original,
					category: fileState.active.file.category
				};
			}

			const currentLocation =
				getCachedData<string>('location.live', {
					ttl: 30 * 60 * 1000,
					version: '1.0'
				}) || '';
			const currentLocationLevels =
				getCachedData<Record<string, string>>('location.levels', {
					ttl: 30 * 60 * 1000,
					version: '1.0'
				}) ?? undefined;
			const currentWeather =
				getCachedData<Record<string, unknown>>('weather.snapshot', {
					ttl: 30 * 60 * 1000,
					version: '1.0'
				}) ?? undefined;
			const currentTimezone =
				typeof window !== 'undefined'
					? Intl.DateTimeFormat().resolvedOptions().timeZone
					: undefined;

			await chatSse.connect({
				assistantMessageId,
				message,
				conversationId: conversationId ?? undefined,
				userMessageId,
				openContext,
				attachments: attachmentsForMessage,
				currentLocation: currentLocation || undefined,
				currentLocationLevels,
				currentWeather,
				currentTimezone
			});
		} catch (error) {
			const errorMessage = error instanceof Error ? error.message : 'Unknown error';
			const friendlyError = getUserFriendlyError(errorMessage);
			toast.error(friendlyError);
			logError('Chat error', error, { scope: 'ChatWindow', conversationId });
			chatStore.setError(assistantMessageId, 'Request failed');
		}
	}

	$: conversationTitle = (() => {
		const conversationId = $chatStore.conversationId;
		if (!conversationId) return 'New Chat';
		const match = $conversationListStore.conversations.find((c) => c.id === conversationId);
		return match?.title || 'New Chat';
	})();

	async function handleNewChat() {
		await chatStore.cleanupEmptyConversation?.();
		await chatStore.startNewConversation();
	}

	function handleCloseChat() {
		chatStore.cleanupEmptyConversation?.();
		chatStore.reset();
	}

	$: {
		const currentId = $chatStore.conversationId;
		if (currentId !== previousConversationId) {
			previousConversationId = currentId;
			attachments = [];
			attachmentPolls.forEach((timeoutId) => clearTimeout(timeoutId));
			attachmentPolls.clear();
		}
	}

	$: hasPendingAttachments = attachments.some((item) => item.status !== 'ready');
	$: readyAttachments = attachments.filter((item) => item.status === 'ready');
	$: pendingAttachments = attachments.filter((item) => item.status !== 'ready');
	$: isSendDisabled = $chatStore.isStreaming || (attachments.length > 0 && hasPendingAttachments);
	$: hasExtendedHeader = Boolean($chatStore.activeTool || $chatStore.promptPreview);
	async function handleAttach(files: FileList) {
		const fileArray = Array.from(files);
		for (const file of fileArray) {
			const id = crypto.randomUUID();
			attachments = [
				...attachments,
				{ id, name: file.name, status: 'uploading', stage: 'uploading', file }
			];
			try {
				const data = await ingestionAPI.upload(file);
				attachments = attachments.map((item) =>
					item.id === id
						? { ...item, fileId: data.file_id, status: 'queued', stage: 'queued' }
						: item
				);
				startAttachmentPolling(id, data.file_id);
			} catch (error) {
				logError('Attachment upload failed', error, { scope: 'ChatWindow', fileName: file.name });
				attachments = attachments.map((item) =>
					item.id === id ? { ...item, status: 'failed', stage: 'failed' } : item
				);
			}
		}
	}

	async function handleRetryAttachment(attachmentId: string) {
		const attachment = attachments.find((item) => item.id === attachmentId);
		if (!attachment) return;
		if (!attachment.file) {
			toast.error('Re-upload the file to retry.');
			return;
		}
		attachments = attachments.map((item) =>
			item.id === attachmentId
				? { ...item, fileId: undefined, status: 'uploading', stage: 'uploading' }
				: item
		);
		try {
			const data = await ingestionAPI.upload(attachment.file);
			attachments = attachments.map((item) =>
				item.id === attachmentId
					? { ...item, fileId: data.file_id, status: 'queued', stage: 'queued' }
					: item
			);
			startAttachmentPolling(attachmentId, data.file_id);
		} catch (error) {
			logError('Attachment upload failed', error, {
				scope: 'ChatWindow',
				attachmentId
			});
			attachments = attachments.map((item) =>
				item.id === attachmentId ? { ...item, status: 'failed', stage: 'failed' } : item
			);
		}
	}

	async function handleDeleteAttachment(attachmentId: string) {
		const attachment = attachments.find((item) => item.id === attachmentId);
		if (!attachment) return;
		const poll = attachmentPolls.get(attachmentId);
		if (poll) clearTimeout(poll);
		attachmentPolls.delete(attachmentId);
		attachments = attachments.filter((item) => item.id !== attachmentId);
		if (attachment.fileId) {
			try {
				await ingestionAPI.delete(attachment.fileId);
			} catch (error) {
				logError('Failed to delete attachment', error, {
					scope: 'ChatWindow',
					attachmentId,
					fileId: attachment.fileId
				});
			}
		}
	}

	function handleRemoveReadyAttachment(attachmentId: string) {
		attachments = attachments.filter((item) => item.id !== attachmentId);
	}

	function startAttachmentPolling(id: string, fileId: string) {
		if (attachmentPolls.has(id)) {
			clearTimeout(attachmentPolls.get(id));
		}
		const poll = async () => {
			try {
				const data = await ingestionAPI.get(fileId);
				const status = data.job.status || 'queued';
				const stage = data.job.stage;
				attachments = attachments.map((item) =>
					item.id === id ? { ...item, status, stage } : item
				);
				if (status === 'ready') {
					ingestionViewerStore.open(fileId);
					ingestionStore.upsertItem({
						file: data.file,
						job: data.job,
						recommended_viewer: data.recommended_viewer
					});
					dispatchCacheEvent('file.uploaded');
				}
				if (!['ready', 'failed', 'canceled'].includes(status) && isMounted) {
					const next = setTimeout(poll, 5000);
					attachmentPolls.set(id, next);
					return;
				}
			} catch (error) {
				logError('Attachment status failed', error, {
					scope: 'ChatWindow',
					attachmentId: id,
					fileId
				});
			}
		};
		const timeoutId = setTimeout(poll, 1500);
		attachmentPolls.set(id, timeoutId);
	}
</script>

<div class="chat-window">
	<div class="chat-header" class:expanded={hasExtendedHeader}>
		<div class="chat-header-row">
			<div class="header-left">
				<MessageSquare size={20} />
				<h2 class="chat-title">{conversationTitle}</h2>
			</div>
			{#if $chatStore.conversationId}
				<div class="header-right">
					{#if $chatStore.isStreaming}
						<span class="streaming-label">Streaming</span>
					{/if}
					<Tooltip disabled={!tooltipsEnabled}>
						<TooltipTrigger>
							{#snippet child({ props })}
								<Button
									size="icon"
									variant="ghost"
									{...props}
									onclick={(event) => {
										props.onclick?.(event);
										handleNewChat(event);
									}}
									aria-label="New chat"
								>
									<Plus size={16} />
								</Button>
							{/snippet}
						</TooltipTrigger>
						<TooltipContent side="bottom">{TOOLTIP_COPY.newChat}</TooltipContent>
					</Tooltip>
					<Tooltip disabled={!tooltipsEnabled}>
						<TooltipTrigger>
							{#snippet child({ props })}
								<Button
									size="icon"
									variant="ghost"
									{...props}
									onclick={(event) => {
										props.onclick?.(event);
										handleCloseChat(event);
									}}
									aria-label="Close chat"
								>
									<X size={16} />
								</Button>
							{/snippet}
						</TooltipTrigger>
						<TooltipContent side="bottom">{TOOLTIP_COPY.closeChat}</TooltipContent>
					</Tooltip>
				</div>
			{/if}
		</div>
		{#if hasExtendedHeader}
			<div class="chat-header-extra">
				{#if $chatStore.activeTool}
					<div class="chat-status-banner" data-status={$chatStore.activeTool.status}>
						{#if $chatStore.activeTool.status === 'running'}
							<Loader2 size={14} class="spin" />
						{:else if $chatStore.activeTool.status === 'success'}
							<CheckCircle2 size={14} />
						{:else}
							<AlertTriangle size={14} />
						{/if}
						<div class="chat-status-text">
							<span class="chat-status-title">{$chatStore.activeTool.name}</span>
							<span class="chat-status-subtitle">
								{$chatStore.activeTool.status === 'running'
									? 'Running'
									: $chatStore.activeTool.status === 'success'
										? 'Success'
										: 'Failed'}
							</span>
						</div>
					</div>
				{/if}
				{#if $chatStore.promptPreview}
					<div class="chat-preview-banner">
						<div class="chat-preview-label">Prompt Preview</div>
						{#if $chatStore.promptPreview.systemPrompt}
							<p class="chat-preview-text">{$chatStore.promptPreview.systemPrompt}</p>
						{/if}
						{#if $chatStore.promptPreview.firstMessagePrompt}
							<p class="chat-preview-text">{$chatStore.promptPreview.firstMessagePrompt}</p>
						{/if}
					</div>
				{/if}
			</div>
		{/if}
	</div>
	<!-- Messages -->
	<MessageList messages={$chatStore.messages} activeTool={$chatStore.activeTool} />

	{#if pendingAttachments.length > 0}
		<div class="chat-attachments">
			{#each pendingAttachments as attachment (attachment.id)}
				<div class="chat-attachment">
					<span class="attachment-name">{attachment.name}</span>
					<div class="attachment-meta">
						{#if attachment.status !== 'ready' && attachment.status !== 'failed'}
							<span class="attachment-spinner" aria-hidden="true"></span>
						{/if}
						<span class="attachment-status">{attachment.stage || attachment.status}</span>
						{#if attachment.status === 'failed'}
							<div class="attachment-actions">
								<Tooltip disabled={!tooltipsEnabled}>
									<TooltipTrigger>
										{#snippet child({ props })}
											<button
												class="attachment-action"
												{...props}
												onclick={(event) => {
													props.onclick?.(event);
													handleRetryAttachment(attachment.id);
												}}
												aria-label="Retry attachment"
											>
												<RotateCcw size={14} />
											</button>
										{/snippet}
									</TooltipTrigger>
									<TooltipContent side="top">{TOOLTIP_COPY.retryAttachment}</TooltipContent>
								</Tooltip>
								<Tooltip disabled={!tooltipsEnabled}>
									<TooltipTrigger>
										{#snippet child({ props })}
											<button
												class="attachment-action"
												{...props}
												onclick={(event) => {
													props.onclick?.(event);
													handleDeleteAttachment(attachment.id);
												}}
												aria-label="Delete attachment"
											>
												<Trash2 size={14} />
											</button>
										{/snippet}
									</TooltipTrigger>
									<TooltipContent side="top">{TOOLTIP_COPY.removeAttachment}</TooltipContent>
								</Tooltip>
							</div>
						{/if}
					</div>
				</div>
			{/each}
		</div>
	{/if}

	<!-- Input -->
	<ChatInput
		onsend={handleSend}
		onattach={handleAttach}
		onremoveattachment={handleRemoveReadyAttachment}
		readyattachments={readyAttachments}
		disabled={isSendDisabled}
	/>
</div>

<style>
	.chat-window {
		display: flex;
		flex-direction: column;
		height: 100%;
		min-height: 0;
		width: 100%;
		background-color: var(--color-background);
		overflow: hidden;
	}

	.chat-header {
		display: flex;
		flex-direction: column;
		align-items: stretch;
		justify-content: center;
		gap: 0.45rem;
		padding: 0.5rem 1.5rem;
		min-height: 57px;
		flex-shrink: 0;
		border-bottom: 1px solid var(--color-border);
		background-color: var(--color-card);
	}

	.chat-header-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.75rem;
	}

	.chat-header.expanded {
		padding-top: 0.45rem;
		padding-bottom: 0.55rem;
	}

	.chat-header-extra {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}

	:global(.dark) .chat-header {
		background: linear-gradient(90deg, rgba(0, 0, 0, 0.04), rgba(0, 0, 0, 0));
	}

	.header-left {
		display: inline-flex;
		align-items: center;
		gap: 0.6rem;
	}

	.header-right {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
	}

	.streaming-label {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-muted-foreground);
		padding-right: 0.25rem;
	}

	.chat-title {
		font-size: 1rem;
		font-weight: 600;
		color: var(--color-foreground);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
		max-width: 300px;
	}

	.chat-status-banner {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.35rem 0.55rem;
		border: 1px solid var(--color-border);
		border-radius: 0.6rem;
		background: color-mix(in oklab, var(--color-card) 82%, transparent);
		width: fit-content;
		max-width: 100%;
	}

	.chat-status-banner[data-status='success'] :global(svg) {
		color: #2f8a4d;
	}

	.chat-status-banner[data-status='error'] :global(svg) {
		color: #d55b5b;
	}

	.chat-status-text {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}

	.chat-status-title {
		font-size: 0.8rem;
		font-weight: 600;
		color: var(--color-foreground);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.chat-status-subtitle {
		font-size: 0.72rem;
		color: var(--color-muted-foreground);
	}

	.chat-preview-banner {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		padding: 0.4rem 0.55rem;
		border: 1px solid var(--color-border);
		border-radius: 0.6rem;
		background: color-mix(in oklab, var(--color-card) 82%, transparent);
	}

	.chat-preview-label {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-muted-foreground);
	}

	.chat-preview-text {
		font-size: 0.76rem;
		color: var(--color-foreground);
		white-space: pre-wrap;
		margin: 0;
	}

	.spin {
		animation: chat-spin 1s linear infinite;
	}

	.chat-attachments {
		padding: 0 1.5rem 0.5rem;
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
		flex-shrink: 0;
	}

	.chat-attachment {
		display: flex;
		justify-content: space-between;
		gap: 0.5rem;
		font-size: 0.8rem;
		color: var(--color-muted-foreground);
	}

	.attachment-name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		color: var(--color-foreground);
	}

	.attachment-status {
		text-transform: uppercase;
		letter-spacing: 0.08em;
	}

	.attachment-meta {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
	}

	.attachment-spinner {
		width: 12px;
		height: 12px;
		border-radius: 999px;
		border: 2px solid color-mix(in oklab, var(--color-muted-foreground) 40%, transparent);
		border-top-color: var(--color-muted-foreground);
		animation: attachment-spin 1s linear infinite;
	}

	.attachment-actions {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
	}

	.attachment-action {
		border: none;
		background: transparent;
		padding: 0;
		cursor: pointer;
		color: var(--color-muted-foreground);
	}

	.attachment-action:hover {
		color: var(--color-foreground);
	}

	@keyframes attachment-spin {
		to {
			transform: rotate(360deg);
		}
	}

	@keyframes chat-spin {
		to {
			transform: rotate(360deg);
		}
	}
</style>
