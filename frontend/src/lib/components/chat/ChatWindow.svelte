<script lang="ts">
	import { onDestroy } from 'svelte';
	import { chatStore } from '$lib/stores/chat';
	import { SSEClient } from '$lib/api/sse';
	import { Button } from '$lib/components/ui/button';
	import { Separator } from '$lib/components/ui/separator';
	import MessageList from './MessageList.svelte';
	import ChatInput from './ChatInput.svelte';
	import { toast } from 'svelte-sonner';
	import { get } from 'svelte/store';
	import { treeStore } from '$lib/stores/tree';
	import { websitesStore } from '$lib/stores/websites';
	import { editorStore } from '$lib/stores/editor';
	import { conversationListStore } from '$lib/stores/conversations';
	import { setThemeMode, type ThemeMode } from '$lib/utils/theme';
	import { scratchpadStore } from '$lib/stores/scratchpad';
	import { memoriesStore } from '$lib/stores/memories';
	import { ingestionAPI } from '$lib/services/api';
	import { MessageSquare, Plus, X } from 'lucide-svelte';
	import { getCachedData } from '$lib/utils/cache';
	import { dispatchCacheEvent } from '$lib/utils/cacheEvents';

	let sseClient = new SSEClient();
	let attachments: Array<{
		id: string;
		fileId?: string;
		name: string;
		status: string;
		stage?: string | null;
	}> = [];
	let attachmentPolls = new Map<string, ReturnType<typeof setTimeout>>();
	let isMounted = true;
	let previousConversationId: string | null = null;

	onDestroy(() => {
		isMounted = false;
		attachmentPolls.forEach((timeoutId) => clearTimeout(timeoutId));
		attachmentPolls.clear();
		// Clean up SSE connection when component unmounts
		sseClient.disconnect();
	});

	/**
	 * Parse error messages and return user-friendly descriptions
	 */
	function getUserFriendlyError(error: string): string {
		// Check for credit balance errors
		if (error.includes('credit balance is too low') || error.includes('insufficient_credits')) {
			return 'API credit balance too low. Please check your Anthropic account billing.';
		}

		// Check for rate limit errors
		if (error.includes('rate_limit') || error.includes('429')) {
			return 'Rate limit exceeded. Please wait a moment and try again.';
		}

		// Check for authentication errors
		if (error.includes('authentication') || error.includes('401')) {
			return 'Authentication failed. Please check your API credentials.';
		}

		// Check for network errors
		if (error.includes('fetch') || error.includes('network')) {
			return 'Network error. Please check your connection and try again.';
		}

		// Default to a generic message
		return 'An error occurred while processing your request. Please try again.';
	}

	function buildPromptPreviewMarkdown(systemPrompt?: string, firstMessagePrompt?: string): string {
		const sections: string[] = [];
		if (systemPrompt) {
			sections.push(`## System Prompt\n\n\`\`\`\n${systemPrompt}\n\`\`\``);
		}
		if (firstMessagePrompt) {
			sections.push(`## First Message Prompt\n\n\`\`\`\n${firstMessagePrompt}\n\`\`\``);
		}
		if (!sections.length) {
			return 'No prompt content was returned.';
		}
		return sections.join('\n\n');
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
			.filter((item) => item.status === 'ready' && item.fileId)
			.map((item) => ({
				file_id: item.fileId,
				filename: item.name
			}));
		attachments = [];

		try {
			// Connect to SSE stream
			const editorState = get(editorStore);
			const websiteState = get(websitesStore);
			const openContext: {
				note?: { id: string; title: string; path: string | null; content: string };
				website?: { id: string; title: string; url: string; domain: string; content: string };
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

			const currentLocation = getCachedData<string>('location.live', {
				ttl: 30 * 60 * 1000,
				version: '1.0'
			}) || '';
			const currentLocationLevels = getCachedData<Record<string, string>>('location.levels', {
				ttl: 30 * 60 * 1000,
				version: '1.0'
			});
			const currentWeather = getCachedData<Record<string, unknown>>('weather.snapshot', {
				ttl: 30 * 60 * 1000,
				version: '1.0'
			});
			const currentTimezone =
				typeof window !== 'undefined'
					? Intl.DateTimeFormat().resolvedOptions().timeZone
					: undefined;

			await sseClient.connect(
				{
					message,
					conversationId: conversationId ?? undefined,
					userMessageId,
					openContext,
					attachments: attachmentsForMessage,
					currentLocation: currentLocation || undefined,
					currentLocationLevels,
					currentWeather,
					currentTimezone
				},
				{
					onToken: (content) => {
						chatStore.appendToken(assistantMessageId, content);
					},

					onToolCall: (event) => {
						chatStore.addToolCall(assistantMessageId, {
							id: event.id,
							name: event.name,
							parameters: event.parameters,
							status: event.status
						});
					},

					onToolResult: (event) => {
						chatStore.updateToolResult(assistantMessageId, event.id, event.result, event.status);
					},
					onToolStart: (event) => {
						if (event?.name) {
							chatStore.setActiveTool(assistantMessageId, event.name, 'running');
						}
					},
					onToolEnd: (event) => {
						const status = event?.status === 'error' ? 'error' : 'success';
						if (event?.name) {
							chatStore.finalizeActiveTool(assistantMessageId, event.name, status);
							if (event.name === 'Web Search') {
								chatStore.markNeedsNewline(assistantMessageId);
							}
						} else {
							chatStore.finalizeActiveTool(assistantMessageId, 'Tool', status);
						}
					},

					onNoteCreated: async (data) => {
						dispatchCacheEvent('note.created');
						if (data?.id && data?.title) {
							treeStore.addNoteNode?.({
								id: data.id,
								name: `${data.title}.md`,
								folder: data.folder
							});
						} else {
							await treeStore.load('notes', true);
						}
						if (data?.id) {
							await editorStore.loadNote('notes', data.id, { source: 'ai' });
						}
					},

					onNoteUpdated: async (data) => {
						dispatchCacheEvent('note.updated');
						if (data?.id && data?.title) {
							treeStore.renameNoteNode?.(data.id, `${data.title}.md`);
						}
						if (data?.id) {
							const editorState = get(editorStore);
							if (editorState.currentNoteId === data.id) {
								await editorStore.loadNote('notes', data.id, { source: 'ai' });
							}
						}
					},

					onWebsiteSaved: async () => {
						dispatchCacheEvent('website.saved');
						await websitesStore.load(true);
					},

					onNoteDeleted: async (data) => {
						const editorState = get(editorStore);
						if (data?.id && editorState.currentNoteId === data.id) {
							editorStore.reset();
						}
						dispatchCacheEvent('note.deleted');
						if (data?.id) {
							treeStore.removeNode?.('notes', data.id);
						} else {
							await treeStore.load('notes', true);
						}
					},

					onWebsiteDeleted: async (data) => {
						dispatchCacheEvent('website.deleted');
						if (data?.id) {
							websitesStore.removeLocal?.(data.id);
						} else {
							await websitesStore.load(true);
						}
					},

					onThemeSet: (data) => {
						const theme = data?.theme === 'dark' ? 'dark' : 'light';
						setThemeMode(theme as ThemeMode);
					},

					onScratchpadUpdated: () => {
						scratchpadStore.bump();
					},

					onScratchpadCleared: () => {
						scratchpadStore.bump();
					},

					onPromptPreview: (data) => {
						const content = buildPromptPreviewMarkdown(
							data?.system_prompt,
							data?.first_message_prompt
						);
						editorStore.openPreview('Prompt Preview', content);
					},

					onMemoryCreated: async () => {
						dispatchCacheEvent('memory.created');
						await memoriesStore.load();
					},

					onMemoryUpdated: async () => {
						dispatchCacheEvent('memory.updated');
						await memoriesStore.load();
					},

					onMemoryDeleted: async () => {
						dispatchCacheEvent('memory.deleted');
						await memoriesStore.load();
					},

					onComplete: async () => {
						await chatStore.finishStreaming(assistantMessageId);
						dispatchCacheEvent('conversation.updated');
					},

					onError: (error) => {
						const friendlyError = getUserFriendlyError(error);
						toast.error(friendlyError);
						console.error('Chat error:', error);
						chatStore.setError(assistantMessageId, 'Request failed');
					}
				}
			);
		} catch (error) {
			const errorMessage = error instanceof Error ? error.message : 'Unknown error';
			const friendlyError = getUserFriendlyError(errorMessage);
			toast.error(friendlyError);
			console.error('Chat error:', error);
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
		await chatStore.startNewConversation();
	}

	function handleCloseChat() {
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
	$: isSendDisabled = $chatStore.isStreaming || (attachments.length > 0 && hasPendingAttachments);

	async function handleAttach(files: FileList) {
		const fileArray = Array.from(files);
		for (const file of fileArray) {
			const id = crypto.randomUUID();
			attachments = [
				...attachments,
				{ id, name: file.name, status: 'uploading', stage: 'uploading' }
			];
			try {
				const data = await ingestionAPI.upload(file);
				attachments = attachments.map((item) =>
					item.id === id ? { ...item, fileId: data.file_id, status: 'queued', stage: 'queued' } : item
				);
				startAttachmentPolling(id, data.file_id);
			} catch (error) {
				console.error('Attachment upload failed:', error);
				attachments = attachments.map((item) =>
					item.id === id ? { ...item, status: 'failed', stage: 'failed' } : item
				);
			}
		}
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
				if (!['ready', 'failed', 'canceled'].includes(status) && isMounted) {
					const next = setTimeout(poll, 5000);
					attachmentPolls.set(id, next);
					return;
				}
			} catch (error) {
				console.error('Attachment status failed:', error);
			}
		};
		const timeoutId = setTimeout(poll, 1500);
		attachmentPolls.set(id, timeoutId);
	}
</script>

<div class="flex flex-col h-full min-h-0 w-full bg-background">
	<div class="chat-header">
		<div class="header-left">
			<MessageSquare size={20} />
			<h2 class="chat-title">{conversationTitle}</h2>
		</div>
		{#if $chatStore.conversationId}
			<div class="header-right">
				<Button
					size="icon"
					variant="ghost"
					onclick={handleNewChat}
					aria-label="New chat"
					title="New chat"
				>
					<Plus size={16} />
				</Button>
				<Button
					size="icon"
					variant="ghost"
					onclick={handleCloseChat}
					aria-label="Close chat"
					title="Close chat"
				>
					<X size={16} />
				</Button>
			</div>
		{/if}
	</div>
	<!-- Messages -->
	<MessageList messages={$chatStore.messages} activeTool={$chatStore.activeTool} />

	{#if attachments.length > 0}
		<div class="chat-attachments">
			{#each attachments as attachment (attachment.id)}
				<div class="chat-attachment">
					<span class="attachment-name">{attachment.name}</span>
					<span class="attachment-status">{attachment.stage || attachment.status}</span>
				</div>
			{/each}
		</div>
	{/if}

	<!-- Input -->
	<ChatInput onsend={handleSend} onattach={handleAttach} disabled={isSendDisabled} />
</div>

<style>
	.chat-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0.5rem 1.5rem;
		min-height: 57px;
		border-bottom: 1px solid var(--color-border);
		background-color: var(--color-card);
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

	.chat-title {
		font-size: 1rem;
		font-weight: 600;
		color: var(--color-foreground);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
		max-width: 300px;
	}

	.chat-attachments {
		padding: 0 1.5rem 0.5rem;
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
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
</style>
