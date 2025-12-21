<script lang="ts">
	import { chatStore } from '$lib/stores/chat';
	import { SSEClient } from '$lib/api/sse';
	import MessageList from './MessageList.svelte';
	import ChatInput from './ChatInput.svelte';

	let sseClient = new SSEClient();

	async function handleSend(message: string) {

		// Add user message and start streaming assistant response
		const assistantMessageId = chatStore.sendMessage(message);

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

				onComplete: () => {
					chatStore.finishStreaming(assistantMessageId);
				},

				onError: (error) => {
					chatStore.setError(assistantMessageId, error);
				}
			});
		} catch (error) {
			console.error('Chat error:', error);
			chatStore.setError(
				assistantMessageId,
				error instanceof Error ? error.message : 'Unknown error'
			);
		}
	}
</script>

<div class="flex flex-col h-screen max-w-5xl mx-auto">
	<!-- Header -->
	<header class="flex items-center justify-between p-4 border-b border-gray-200 bg-white">
		<div>
			<h1 class="text-2xl font-bold">Agent Smith</h1>
			<p class="text-sm text-gray-500">AI Assistant with Tool Access</p>
		</div>
		<button
			onclick={() => chatStore.clear()}
			class="px-4 py-2 text-sm text-gray-600 hover:text-gray-800 hover:bg-gray-100 rounded transition-colors"
		>
			Clear Chat
		</button>
	</header>

	<!-- Messages -->
	<MessageList messages={$chatStore.messages} />

	<!-- Input -->
	<ChatInput onsend={handleSend} disabled={$chatStore.isStreaming} />
</div>
