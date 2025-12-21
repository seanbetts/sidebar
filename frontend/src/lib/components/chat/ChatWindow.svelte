<script lang="ts">
	import { chatStore } from '$lib/stores/chat';
	import { SSEClient } from '$lib/api/sse';
	import { Button } from '$lib/components/ui/button';
	import { Separator } from '$lib/components/ui/separator';
	import ModeToggle from '$lib/components/mode-toggle.svelte';
	import MessageList from './MessageList.svelte';
	import ChatInput from './ChatInput.svelte';
	import { toast } from 'svelte-sonner';

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
		const assistantMessageId = await chatStore.sendMessage(message);

		try {
			// Connect to SSE stream
			await sseClient.connect(message, {
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

				onComplete: async () => {
					await chatStore.finishStreaming(assistantMessageId);
				},

				onError: (error) => {
					const friendlyError = getUserFriendlyError(error);
					toast.error(friendlyError);
					console.error('Chat error:', error);
					chatStore.setError(assistantMessageId, 'Request failed');
				}
			});
		} catch (error) {
			const errorMessage = error instanceof Error ? error.message : 'Unknown error';
			const friendlyError = getUserFriendlyError(errorMessage);
			toast.error(friendlyError);
			console.error('Chat error:', error);
			chatStore.setError(assistantMessageId, 'Request failed');
		}
	}
</script>

<div class="flex flex-col h-screen max-w-6xl mx-auto bg-background">
	<!-- Header -->
	<header class="flex items-center justify-between p-4 border-b">
		<div>
			<h1 class="text-2xl font-bold text-foreground">Agent Smith</h1>
			<p class="text-sm text-muted-foreground">AI Assistant with Tool Access</p>
		</div>
		<ModeToggle />
	</header>

	<!-- Messages -->
	<MessageList messages={$chatStore.messages} />

	<!-- Input -->
	<ChatInput onsend={handleSend} disabled={$chatStore.isStreaming} />
</div>
