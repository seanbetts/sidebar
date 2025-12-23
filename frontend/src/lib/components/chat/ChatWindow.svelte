<script lang="ts">
	import { chatStore } from '$lib/stores/chat';
	import { SSEClient } from '$lib/api/sse';
	import { Button } from '$lib/components/ui/button';
	import { Separator } from '$lib/components/ui/separator';
	import MessageList from './MessageList.svelte';
	import ChatInput from './ChatInput.svelte';
	import { toast } from 'svelte-sonner';
	import { get } from 'svelte/store';
	import { filesStore } from '$lib/stores/files';
	import { websitesStore } from '$lib/stores/websites';
	import { editorStore } from '$lib/stores/editor';
	import { conversationListStore } from '$lib/stores/conversations';
	import { setThemeMode, type ThemeMode } from '$lib/utils/theme';
	import { scratchpadStore } from '$lib/stores/scratchpad';
	import { MessageSquare } from 'lucide-svelte';

	let sseClient = new SSEClient();

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

	async function handleSend(message: string) {

		// Add user message and start streaming assistant response
		const { assistantMessageId, userMessageId } = await chatStore.sendMessage(message);
		const { conversationId } = get(chatStore);

		try {
			// Connect to SSE stream
			await sseClient.connect(
				{
					message,
					conversationId: conversationId ?? undefined,
					userMessageId
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

					onNoteCreated: async (data) => {
						await filesStore.load('notes');
						if (data?.id) {
							await editorStore.loadNote('notes', data.id, { source: 'ai' });
						}
					},

					onNoteUpdated: async (data) => {
						await filesStore.load('notes');
						if (data?.id) {
							const editorState = get(editorStore);
							if (editorState.currentNoteId === data.id) {
								await editorStore.loadNote('notes', data.id, { source: 'ai' });
							}
						}
					},

					onWebsiteSaved: async () => {
						await websitesStore.load();
					},

					onNoteDeleted: async (data) => {
						const editorState = get(editorStore);
						if (data?.id && editorState.currentNoteId === data.id) {
							editorStore.reset();
						}
						await filesStore.load('notes');
					},

					onWebsiteDeleted: async () => {
						await websitesStore.load();
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

					onComplete: async () => {
						await chatStore.finishStreaming(assistantMessageId);
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
</script>

<div class="flex flex-col h-full min-h-0 max-w-6xl mx-auto bg-background">
	<div class="chat-header">
		<div class="header-left">
			<MessageSquare size={20} />
			<h2 class="chat-title">{conversationTitle}</h2>
		</div>
	</div>
	<!-- Messages -->
	<MessageList messages={$chatStore.messages} />

	<!-- Input -->
	<ChatInput onsend={handleSend} disabled={$chatStore.isStreaming} />
</div>

<style>
	.chat-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 1rem 1.5rem;
		min-height: 57px;
		border-bottom: 1px solid var(--color-border);
		background-color: var(--color-card);
	}

	.header-left {
		display: inline-flex;
		align-items: center;
		gap: 0.6rem;
	}

	.chat-title {
		font-size: 1rem;
		font-weight: 600;
		color: var(--color-foreground);
	}
</style>
