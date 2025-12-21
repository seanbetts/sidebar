<script lang="ts">
	import { chatStore } from '$lib/stores/chat';
	import { SSEClient } from '$lib/api/sse';
	import { Button } from '$lib/components/ui/button';
	import { Separator } from '$lib/components/ui/separator';
	import ModeToggle from '$lib/components/mode-toggle.svelte';
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

<div class="flex flex-col h-screen max-w-6xl mx-auto bg-background">
	<!-- Header -->
	<header class="flex items-center justify-between p-4 border-b">
		<div>
			<h1 class="text-2xl font-bold text-foreground">Agent Smith</h1>
			<p class="text-sm text-muted-foreground">AI Assistant with Tool Access</p>
		</div>
		<div class="flex items-center gap-2">
			<Button variant="outline" size="sm" onclick={() => chatStore.clear()}>
				Clear Chat
			</Button>
			<ModeToggle />
		</div>
	</header>

	<!-- Messages -->
	<MessageList messages={$chatStore.messages} />

	<!-- Input -->
	<ChatInput onsend={handleSend} disabled={$chatStore.isStreaming} />
</div>
