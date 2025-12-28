/**
 * Chat store for managing messages and streaming state
 */
import { writable, get } from 'svelte/store';
import type { Message, ToolCall } from '$lib/types/chat';
import { conversationsAPI } from '$lib/services/api';
import { conversationListStore, currentConversationId } from './conversations';
import { generateConversationTitle } from './chat/generateTitle';

export interface ChatState {
	messages: Message[];
	isStreaming: boolean;
	currentMessageId: string | null;
	conversationId: string | null;
	activeTool: {
		messageId: string;
		name: string;
		status: 'running' | 'success' | 'error';
		startedAt: number;
	} | null;
}

function createChatStore() {
	const { subscribe, set, update } = writable<ChatState>({
		messages: [],
		isStreaming: false,
		currentMessageId: null,
		conversationId: null,
		activeTool: null
	});
	let toolClearTimeout: ReturnType<typeof setTimeout> | null = null;
	let toolUpdateTimeout: ReturnType<typeof setTimeout> | null = null;

	return {
		subscribe,

		/**
		 * Load an existing conversation
		 */
		async loadConversation(conversationId: string) {
			const conversation = await conversationsAPI.get(conversationId);
			currentConversationId.set(conversationId);
			set({
				conversationId,
				messages: conversation.messages.map(msg => ({
					...msg,
					timestamp: new Date(msg.timestamp)
				})),
				isStreaming: false,
				currentMessageId: null,
				activeTool: null
			});
		},

		/**
		 * Start a new conversation
		 */
		async startNewConversation() {
			const conversation = await conversationsAPI.create();
			currentConversationId.set(conversation.id);
			set({
				conversationId: conversation.id,
				messages: [],
				isStreaming: false,
				currentMessageId: null,
				activeTool: null
			});

			// Mark as generating title from the start
			conversationListStore.setGeneratingTitle(conversation.id, true);

			// Add conversation to sidebar without full refresh
			conversationListStore.addConversation(conversation);

			return conversation.id;
		},

		/**
		 * Add a user message and start streaming assistant response
		 */
		async sendMessage(content: string): Promise<{
			assistantMessageId: string;
			userMessageId: string;
		}> {
			const state = get({ subscribe });

			// Create new conversation if none exists
			if (!state.conversationId) {
				await this.startNewConversation();
			}

			const userMessageId = crypto.randomUUID();
			const assistantMessageId = crypto.randomUUID();

			const userMessage: Message = {
				id: userMessageId,
				role: 'user',
				content,
				status: 'complete',
				timestamp: new Date()
			};

			update((state) => ({
				...state,
				messages: [
					...state.messages,
					userMessage,
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
				currentMessageId: assistantMessageId,
				activeTool: null
			}));

			// Persist user message to backend
			const currentState = get({ subscribe });
			if (currentState.conversationId) {
				try {
					await conversationsAPI.addMessage(currentState.conversationId, userMessage);
				} catch (error) {
					console.error('Failed to persist user message:', error);
				}
			}

			return { assistantMessageId, userMessageId };
		},

		/**
		 * Append token to current streaming message
		 */
		appendToken(messageId: string, token: string) {
			update((state) => ({
				...state,
				messages: state.messages.map((msg) => {
					if (msg.id !== messageId) return msg;

					let prefix = '';
					if (msg.needsNewline && msg.content) {
						if (!msg.content.endsWith('\n') && !token.startsWith('\n')) {
							prefix = '\n\n';
						}
					}

					return {
						...msg,
						content: msg.content + prefix + token,
						needsNewline: msg.needsNewline ? false : msg.needsNewline
					};
				})
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
						),
						needsNewline: true
					};
				})
			}));
		},

		/**
		 * Mark streaming as complete
		 */
		async finishStreaming(messageId: string) {
			update((state) => ({
				...state,
				messages: state.messages.map((msg) =>
					msg.id === messageId ? { ...msg, status: 'complete' } : msg
				),
				isStreaming: false,
				currentMessageId: null
			}));

			// Persist assistant message to backend
			const state = get({ subscribe });
			const assistantMessage = state.messages.find(m => m.id === messageId);

			if (state.conversationId && assistantMessage) {
				try {
					await conversationsAPI.addMessage(state.conversationId, assistantMessage);

					const messageCount = state.messages.length;

					// Check if this is the first exchange (2 messages total)
					if (messageCount === 2) {
						const firstMessage = state.messages[0]?.content.substring(0, 100);

						// Update conversation metadata (message count and preview)
						conversationListStore.updateConversationMetadata(state.conversationId, {
							messageCount,
							firstMessage,
							updatedAt: new Date().toISOString()
						});

						// Trigger title generation (generating state was set when conversation was created)
						generateConversationTitle(state.conversationId).catch(err => {
							console.error('Title generation failed:', err);
						});
					} else {
						// For subsequent messages, just update the metadata
						conversationListStore.updateConversationMetadata(state.conversationId, {
							messageCount,
							updatedAt: new Date().toISOString()
						});
					}
				} catch (error) {
					console.error('Failed to persist assistant message:', error);
				}
			}
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
				currentMessageId: null,
				activeTool: null
			}));
		},

		/**
		 * Reset to empty state without creating a conversation
		 */
		reset() {
			set({
				conversationId: null,
				messages: [],
				isStreaming: false,
				currentMessageId: null,
				activeTool: null
			});
		},

		/**
		 * Clear all messages (starts new conversation)
		 */
		async clear() {
			await this.startNewConversation();
		},

		setActiveTool(messageId: string, name: string, status: 'running' | 'success' | 'error') {
			if (toolClearTimeout) {
				clearTimeout(toolClearTimeout);
				toolClearTimeout = null;
			}
			if (toolUpdateTimeout) {
				clearTimeout(toolUpdateTimeout);
				toolUpdateTimeout = null;
			}
			const startedAt = Date.now();
			update((state) => ({
				...state,
				activeTool: {
					messageId,
					name,
					status,
					startedAt
				}
			}));
		},

		finalizeActiveTool(
			messageId: string,
			name: string,
			status: 'success' | 'error',
			minRunningMs: number = 250,
			displayMs: number = 4500
		) {
			if (toolClearTimeout) {
				clearTimeout(toolClearTimeout);
				toolClearTimeout = null;
			}
			if (toolUpdateTimeout) {
				clearTimeout(toolUpdateTimeout);
				toolUpdateTimeout = null;
			}
			const now = Date.now();
			const startedAt = this.getActiveToolStartTime(messageId, name) ?? now;
			const elapsed = now - startedAt;
			const updateDelay = Math.max(0, minRunningMs - elapsed);

			toolUpdateTimeout = setTimeout(() => {
				update((state) => ({
					...state,
					activeTool: state.activeTool?.messageId === messageId
						? { ...state.activeTool, status, startedAt }
						: state.activeTool
				}));
				toolUpdateTimeout = null;

				if (status === 'error') {
					toolClearTimeout = setTimeout(() => {
						update((state) => ({
							...state,
							messages: state.messages.map((msg) =>
								msg.id === messageId ? { ...msg, needsNewline: true } : msg
							),
							activeTool: state.activeTool?.messageId === messageId ? null : state.activeTool
						}));
						toolClearTimeout = null;
					}, displayMs);
				}
			}, updateDelay);
		},

		markNeedsNewline(messageId: string) {
			update((state) => ({
				...state,
				messages: state.messages.map((msg) =>
					msg.id === messageId ? { ...msg, needsNewline: true } : msg
				)
			}));
		},

		getActiveToolStartTime(messageId: string, name: string) {
			const state = get({ subscribe });
			if (!state.activeTool) return null;
			if (state.activeTool.messageId !== messageId) return null;
			if (state.activeTool.name !== name) return null;
			return state.activeTool.startedAt;
		}
	};
}

export const chatStore = createChatStore();
