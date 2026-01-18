import { SSEClient } from '$lib/api/sse';
import { chatStore } from '$lib/stores/chat';
import { treeStore } from '$lib/stores/tree';
import { websitesStore } from '$lib/stores/websites';
import { editorStore, currentNoteId } from '$lib/stores/editor';
import { ingestionViewerStore } from '$lib/stores/ingestion-viewer';
import { ingestionStore } from '$lib/stores/ingestion';
import { scratchpadStore } from '$lib/stores/scratchpad';
import { memoriesStore } from '$lib/stores/memories';
import { dispatchCacheEvent } from '$lib/utils/cacheEvents';
import { setThemeMode, type ThemeMode } from '$lib/utils/theme';
import { logError } from '$lib/utils/errorHandling';
import { get } from 'svelte/store';
import { toast } from 'svelte-sonner';
import { markFirstEvent, markSseError } from '$lib/utils/chatMetrics';
import { ingestionAPI } from '$lib/services/api';

export interface ChatSSEConnectArgs {
	assistantMessageId: string;
	message: string;
	conversationId?: string;
	userMessageId?: string;
	openContext?: Record<string, unknown>;
	attachments?: Array<{ file_id: string; filename: string }>;
	currentLocation?: string;
	currentLocationLevels?: Record<string, string>;
	currentWeather?: Record<string, unknown>;
	currentTimezone?: string;
}

/**
 * Parse error messages and return user-friendly descriptions.
 *
 * @param error Raw error message string.
 * @returns Friendly error message for display.
 */
export function getUserFriendlyError(error: string): string {
	if (error.includes('credit balance is too low') || error.includes('insufficient_credits')) {
		return 'API credit balance too low. Please check your Anthropic account billing.';
	}
	if (error.includes('rate_limit') || error.includes('429')) {
		return 'Rate limit exceeded. Please wait a moment and try again.';
	}
	if (error.includes('authentication') || error.includes('401')) {
		return 'Authentication failed. Please check your API credentials.';
	}
	if (error.includes('fetch') || error.includes('network')) {
		return 'Network error. Please check your connection and try again.';
	}
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

/**
 * Provide SSE connection helpers for chat streaming.
 *
 * @returns Chat SSE connection helpers.
 */
export function useChatSSE() {
	const sseClient = new SSEClient();

	async function connect({ assistantMessageId, ...payload }: ChatSSEConnectArgs) {
		const { conversationId } = payload;
		await sseClient.connect(payload, {
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
				websitesStore.clearActive();
				ingestionViewerStore.clearActive();
				currentNoteId.set(null);
				if (data?.id && data?.title) {
					treeStore.addNoteNode?.({
						id: data.id,
						name: `${data.title}.md`,
						folder: data.folder
					});
				}
				if (data?.id) {
					await editorStore.loadNote('notes', data.id, { source: 'ai' });
				}
			},

			onNoteUpdated: async (data) => {
				dispatchCacheEvent('note.updated');
				websitesStore.clearActive();
				ingestionViewerStore.clearActive();
				currentNoteId.set(null);
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

			onNotePinned: (data) => {
				if (data?.id && data?.pinned !== undefined) {
					treeStore.setNotePinned?.(data.id, data.pinned);
				}
				dispatchCacheEvent('note.pinned');
			},

			onNoteMoved: (data) => {
				if (data?.id && data?.folder !== undefined) {
					treeStore.moveNoteNode?.(data.id, data.folder);
				}
				dispatchCacheEvent('note.moved');
			},

			onWebsiteSaved: async () => {
				dispatchCacheEvent('website.saved');
			},

			onWebsitePinned: (data) => {
				if (data?.id && data?.pinned !== undefined) {
					websitesStore.setPinnedLocal?.(data.id, data.pinned);
					websitesStore.updateActiveLocal?.({
						pinned: data.pinned,
						...(data.pinned ? { archived: false } : {})
					});
				}
				dispatchCacheEvent('website.pinned');
			},

			onWebsiteArchived: (data) => {
				if (data?.id && data?.archived !== undefined) {
					websitesStore.setArchivedLocal?.(data.id, data.archived);
					websitesStore.updateActiveLocal?.({ archived: data.archived });
				}
				dispatchCacheEvent('website.archived');
			},

			onNoteDeleted: async (data) => {
				const editorState = get(editorStore);
				if (data?.id && editorState.currentNoteId === data.id) {
					editorStore.reset();
				}
				dispatchCacheEvent('note.deleted');
				if (data?.id) {
					treeStore.removeNode?.('notes', data.id);
				}
			},

			onWebsiteDeleted: async (data) => {
				dispatchCacheEvent('website.deleted');
				if (data?.id) {
					websitesStore.removeLocal?.(data.id);
				}
			},

			onIngestionUpdated: async (data) => {
				const fileId = data?.file_id;
				if (!fileId) return;
				try {
					const meta = await ingestionAPI.get(fileId);
					ingestionStore.upsertItem({
						file: meta.file,
						job: meta.job,
						recommended_viewer: meta.recommended_viewer
					});
					const viewerState = get(ingestionViewerStore);
					if (viewerState.active?.file.id === fileId) {
						ingestionViewerStore.setActive(meta);
					}
				} catch (error) {
					logError('Failed to fetch ingestion metadata', error, {
						scope: 'chatSSE.ingestionUpdated',
						fileId
					});
				}
			},

			onThemeSet: (data) => {
				const theme = data?.theme === 'dark' ? 'dark' : 'light';
				setThemeMode(theme as ThemeMode, 'ai');
			},

			onScratchpadUpdated: () => {
				scratchpadStore.bump();
			},

			onScratchpadCleared: () => {
				scratchpadStore.bump();
			},

			onPromptPreview: (data) => {
				const content = buildPromptPreviewMarkdown(data?.system_prompt, data?.first_message_prompt);
				websitesStore.clearActive();
				ingestionViewerStore.clearActive();
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

			onFirstEvent: ({ elapsedMs }) => {
				markFirstEvent(assistantMessageId, elapsedMs);
			},

			onComplete: async () => {
				await chatStore.finishStreaming(assistantMessageId);
				dispatchCacheEvent('conversation.updated');
			},

			onError: (error) => {
				const friendlyError = getUserFriendlyError(error);
				toast.error(friendlyError);
				logError('Chat error', error, { scope: 'chatSSE.onError', conversationId });
				markSseError(assistantMessageId);
				chatStore.setError(assistantMessageId, 'Request failed');
			}
		});
	}

	function disconnect() {
		sseClient.disconnect();
	}

	return { connect, disconnect };
}
