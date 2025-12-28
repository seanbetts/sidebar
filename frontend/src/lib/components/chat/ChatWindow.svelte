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
	import { filesStore } from '$lib/stores/files';
	import { websitesStore } from '$lib/stores/websites';
	import { editorStore } from '$lib/stores/editor';
	import { conversationListStore } from '$lib/stores/conversations';
	import { setThemeMode, type ThemeMode } from '$lib/utils/theme';
	import { scratchpadStore } from '$lib/stores/scratchpad';
	import { memoriesStore } from '$lib/stores/memories';
	import { MessageSquare, Plus, X } from 'lucide-svelte';

	let sseClient = new SSEClient();

	onDestroy(() => {
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

		// Add user message and start streaming assistant response
		const { assistantMessageId, userMessageId } = await chatStore.sendMessage(message);
		const { conversationId } = get(chatStore);

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

			const currentLocation =
				typeof window !== 'undefined' ? localStorage.getItem('sidebar.liveLocation') || '' : '';
			let currentLocationLevels: Record<string, string> | undefined;
			const rawLevels =
				typeof window !== 'undefined' ? localStorage.getItem('sidebar.liveLocationLevels') : null;
			if (rawLevels) {
				try {
					currentLocationLevels = JSON.parse(rawLevels);
				} catch (error) {
					console.error('Failed to parse live location levels:', error);
				}
			}
			let currentWeather: Record<string, unknown> | undefined;
			const rawWeather =
				typeof window !== 'undefined' ? localStorage.getItem('sidebar.weather') : null;
			if (rawWeather) {
				try {
					currentWeather = JSON.parse(rawWeather);
				} catch (error) {
					console.error('Failed to parse weather cache:', error);
				}
			}
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

					onPromptPreview: (data) => {
						const content = buildPromptPreviewMarkdown(
							data?.system_prompt,
							data?.first_message_prompt
						);
						editorStore.openPreview('Prompt Preview', content);
					},

					onMemoryCreated: async () => {
						await memoriesStore.load();
					},

					onMemoryUpdated: async () => {
						await memoriesStore.load();
					},

					onMemoryDeleted: async () => {
						await memoriesStore.load();
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

	async function handleNewChat() {
		await chatStore.startNewConversation();
	}

	function handleCloseChat() {
		chatStore.reset();
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

	<!-- Input -->
	<ChatInput onsend={handleSend} disabled={$chatStore.isStreaming} />
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
</style>
