/**
 * Chat store for managing messages and streaming state
 */
import { writable, get } from 'svelte/store';
import { browser } from '$app/environment';
import type { Message, ToolCall } from '$lib/types/chat';
import { conversationsAPI } from '$lib/services/api';
import { conversationListStore, currentConversationId } from './conversations';
import { generateConversationTitle } from './chat/generateTitle';
import { createToolStateHandlers } from './chat/toolState';
import { dispatchCacheEvent } from '$lib/utils/cacheEvents';
import { ingestionAPI } from '$lib/services/api';
import { ingestionStore } from '$lib/stores/ingestion';
import { logError } from '$lib/utils/errorHandling';
import {
	startChatStream,
	markFirstToken,
	markStreamComplete,
	markStreamError
} from '$lib/utils/chatMetrics';

const LAST_CONVERSATION_KEY = 'sideBar.lastConversation';

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
	const getState = () => get({ subscribe });
	const toolState = createToolStateHandlers(update, getState);
	const cleanupEmptyConversation = async () => {
		const state = get({ subscribe });
		if (!state.conversationId || state.messages.length > 0 || state.isStreaming) {
			return;
		}
		await conversationListStore.deleteConversation(state.conversationId);
		currentConversationId.set(null);
		clearLastConversation();
		set({
			...state,
			conversationId: null
		});
	};

	const setLastConversationId = (conversationId: string) => {
		if (!browser) return;
		try {
			localStorage.setItem(LAST_CONVERSATION_KEY, conversationId);
		} catch (error) {
			console.warn('Failed to persist last conversation:', error);
		}
	};

	const clearLastConversation = () => {
		if (!browser) return;
		try {
			localStorage.removeItem(LAST_CONVERSATION_KEY);
		} catch {
			// Ignore storage errors.
		}
	};

	return {
		subscribe,

		/**
		 * Load an existing conversation
		 * @param conversationId Conversation id to load.
		 */
		async loadConversation(conversationId: string) {
			toolState.clearToolTimers();
			await cleanupEmptyConversation();
			const conversation = await conversationsAPI.get(conversationId);
			currentConversationId.set(conversationId);
			setLastConversationId(conversationId);
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
		 * @returns New conversation id.
		 */
		async startNewConversation() {
			toolState.clearToolTimers();
			await cleanupEmptyConversation();
			const conversation = await conversationsAPI.create();
			currentConversationId.set(conversation.id);
			setLastConversationId(conversation.id);
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
			dispatchCacheEvent('conversation.created');

			return conversation.id;
		},

		/**
		 * Add a user message and start streaming assistant response
		 * @param content User message content.
		 * @returns Assistant/user message ids for the streaming pair.
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
			startChatStream(assistantMessageId);

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
					logError('Failed to persist user message', error, {
						scope: 'chatStore.sendMessage',
						conversationId: currentState.conversationId
					});
				}
			}

			return { assistantMessageId, userMessageId };
		},

		/**
		 * Append token to current streaming message
		 * @param messageId Message id to append to.
		 * @param token Streamed token content.
		 */
		appendToken(messageId: string, token: string) {
			markFirstToken(messageId);
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
		 * @param messageId Message id to update.
		 * @param toolCall Tool call data.
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
		 * @param messageId Message id to update.
		 * @param toolCallId Tool call id to update.
		 * @param result Tool result payload.
		 * @param status Tool result status.
		 */
		updateToolResult(messageId: string, toolCallId: string, result: any, status: 'success' | 'error') {
			const state = get({ subscribe });
			const toolName = state.messages
				.find((msg) => msg.id === messageId)
				?.toolCalls?.find((tc) => tc.id === toolCallId)
				?.name
				?.toLowerCase();
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
			if (status === 'success' && toolName && (toolName.includes('fs.write') || toolName === 'write file')) {
				const fileId = result?.data?.file_id ?? result?.data?.fileId;
				if (!fileId) return;
				void ingestionAPI
					.get(fileId)
					.then((meta) => {
						ingestionStore.upsertItem({
							file: meta.file,
							job: meta.job,
							recommended_viewer: meta.recommended_viewer
						});
					})
					.catch((error) => {
						logError('Failed to fetch ingestion metadata', error, {
							scope: 'chatStore.fetchIngestionMetadata',
							fileId
						});
					});
			}
		},

		/**
		 * Mark streaming as complete
		 * @param messageId Message id to finalize.
		 */
		async finishStreaming(messageId: string) {
			markStreamComplete(messageId);
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

						conversationListStore.setGeneratingTitle(state.conversationId, true);

						// Update conversation metadata (message count and preview)
						conversationListStore.updateConversationMetadata(state.conversationId, {
							messageCount,
							firstMessage,
							updatedAt: new Date().toISOString()
						});

						// Trigger title generation (generating state was set when conversation was created)
						generateConversationTitle(state.conversationId).catch(err => {
							logError('Title generation failed', err, {
								scope: 'chatStore.generateTitle',
								conversationId: state.conversationId
							});
						});
					} else {
						// For subsequent messages, just update the metadata
						conversationListStore.updateConversationMetadata(state.conversationId, {
							messageCount,
							updatedAt: new Date().toISOString()
						});
					}
				} catch (error) {
					logError('Failed to persist assistant message', error, {
						scope: 'chatStore.persistAssistant',
						conversationId: state.conversationId
					});
				}
			}
		},

		/**
		 * Set error on current message
		 * @param messageId Message id to mark as error.
		 * @param error Error message to attach.
		 */
		setError(messageId: string, error: string) {
			markStreamError(messageId);
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
			toolState.clearToolTimers();
			void cleanupEmptyConversation();
			set({
				conversationId: null,
				messages: [],
				isStreaming: false,
				currentMessageId: null,
				activeTool: null
			});
			clearLastConversation();
		},

		/**
		 * Clear all messages (starts new conversation)
		 */
		async clear() {
			await this.startNewConversation();
		},

		getLastConversationId(): string | null {
			if (!browser) return null;
			try {
				return localStorage.getItem(LAST_CONVERSATION_KEY);
			} catch {
				return null;
			}
		},

		clearLastConversation,
		cleanup() {
			toolState.cleanup?.();
		},

		setActiveTool: toolState.setActiveTool,
		finalizeActiveTool: toolState.finalizeActiveTool,
		markNeedsNewline: toolState.markNeedsNewline,
		getActiveToolStartTime: toolState.getActiveToolStartTime,
		cleanupEmptyConversation
	};
}

export const chatStore = createChatStore();
