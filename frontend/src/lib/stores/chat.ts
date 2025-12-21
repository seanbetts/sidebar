/**
 * Chat store for managing messages and streaming state
 */
import { writable } from 'svelte/store';
import type { Message, ToolCall } from '$lib/types/chat';

export interface ChatState {
	messages: Message[];
	isStreaming: boolean;
	currentMessageId: string | null;
}

function createChatStore() {
	const { subscribe, set, update } = writable<ChatState>({
		messages: [],
		isStreaming: false,
		currentMessageId: null
	});

	return {
		subscribe,

		/**
		 * Add a user message and start streaming assistant response
		 */
		sendMessage(content: string): string {
			const userMessageId = crypto.randomUUID();
			const assistantMessageId = crypto.randomUUID();

			update((state) => ({
				...state,
				messages: [
					...state.messages,
					{
						id: userMessageId,
						role: 'user',
						content,
						status: 'complete',
						timestamp: new Date()
					},
					{
						id: assistantMessageId,
						role: 'assistant',
						content: '',
						status: 'streaming',
						toolCalls: [],
						timestamp: new Date()
					}
				],
				isStreaming: true,
				currentMessageId: assistantMessageId
			}));

			return assistantMessageId;
		},

		/**
		 * Append token to current streaming message
		 */
		appendToken(messageId: string, token: string) {
			update((state) => ({
				...state,
				messages: state.messages.map((msg) =>
					msg.id === messageId ? { ...msg, content: msg.content + token } : msg
				)
			}));
		},

		/**
		 * Add or update tool call in current message
		 */
		addToolCall(messageId: string, toolCall: ToolCall) {
			update((state) => ({
				...state,
				messages: state.messages.map((msg) => {
					if (msg.id !== messageId) return msg;

					const existingIndex = msg.toolCalls?.findIndex((tc) => tc.id === toolCall.id);

					if (existingIndex !== undefined && existingIndex >= 0) {
						// Update existing tool call
						const updatedToolCalls = [...(msg.toolCalls || [])];
						updatedToolCalls[existingIndex] = toolCall;
						return { ...msg, toolCalls: updatedToolCalls };
					} else {
						// Add new tool call
						return {
							...msg,
							toolCalls: [...(msg.toolCalls || []), toolCall]
						};
					}
				})
			}));
		},

		/**
		 * Update tool call result
		 */
		updateToolResult(messageId: string, toolCallId: string, result: any, status: 'success' | 'error') {
			update((state) => ({
				...state,
				messages: state.messages.map((msg) => {
					if (msg.id !== messageId) return msg;

					return {
						...msg,
						toolCalls: msg.toolCalls?.map((tc) =>
							tc.id === toolCallId ? { ...tc, result, status } : tc
						)
					};
				})
			}));
		},

		/**
		 * Mark streaming as complete
		 */
		finishStreaming(messageId: string) {
			update((state) => ({
				...state,
				messages: state.messages.map((msg) =>
					msg.id === messageId ? { ...msg, status: 'complete' } : msg
				),
				isStreaming: false,
				currentMessageId: null
			}));
		},

		/**
		 * Set error on current message
		 */
		setError(messageId: string, error: string) {
			update((state) => ({
				...state,
				messages: state.messages.map((msg) =>
					msg.id === messageId ? { ...msg, status: 'error', error } : msg
				),
				isStreaming: false,
				currentMessageId: null
			}));
		},

		/**
		 * Clear all messages
		 */
		clear() {
			set({
				messages: [],
				isStreaming: false,
				currentMessageId: null
			});
		}
	};
}

export const chatStore = createChatStore();
