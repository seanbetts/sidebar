import type { ChatState } from '../chat';
import { markToolEnd, markToolStart } from '$lib/utils/chatMetrics';

type UpdateFn = (updater: (state: ChatState) => ChatState) => void;
type GetStateFn = () => ChatState;

/**
 * Create helpers for managing tool status state in the chat store.
 *
 * @param update - Store update function.
 * @param getState - Store state getter.
 * @returns Tool state handler helpers.
 */
export function createToolStateHandlers(update: UpdateFn, getState: GetStateFn) {
	let toolClearTimeout: ReturnType<typeof setTimeout> | null = null;
	let toolUpdateTimeout: ReturnType<typeof setTimeout> | null = null;

	const clearToolTimers = () => {
		if (toolClearTimeout) {
			clearTimeout(toolClearTimeout);
			toolClearTimeout = null;
		}
		if (toolUpdateTimeout) {
			clearTimeout(toolUpdateTimeout);
			toolUpdateTimeout = null;
		}
	};

	const getActiveToolStartTime = (messageId: string, name: string) => {
		const state = getState();
		if (!state.activeTool) return null;
		if (state.activeTool.messageId !== messageId) return null;
		if (state.activeTool.name !== name) return null;
		return state.activeTool.startedAt;
	};

	const setActiveTool = (
		messageId: string,
		name: string,
		status: 'running' | 'success' | 'error'
	) => {
		clearToolTimers();
		const startedAt = Date.now();
		markToolStart(messageId, name);
		update((state) => ({
			...state,
			activeTool: {
				messageId,
				name,
				status,
				startedAt
			}
		}));
	};

	const finalizeActiveTool = (
		messageId: string,
		name: string,
		status: 'success' | 'error',
		minRunningMs: number = 250,
		displayMs: number = 4500
	) => {
		clearToolTimers();
		const now = Date.now();
		const startedAt = getActiveToolStartTime(messageId, name) ?? now;
		const elapsed = now - startedAt;
		const updateDelay = Math.max(0, minRunningMs - elapsed);
		markToolEnd(messageId, name, status);

		toolUpdateTimeout = setTimeout(() => {
			update((state) => ({
				...state,
				activeTool:
					state.activeTool?.messageId === messageId
						? { ...state.activeTool, status, startedAt }
						: state.activeTool
			}));
			toolUpdateTimeout = null;

			toolClearTimeout = setTimeout(() => {
				update((state) => ({
					...state,
					messages:
						status === 'error'
							? state.messages.map((msg) =>
									msg.id === messageId ? { ...msg, needsNewline: true } : msg
								)
							: state.messages,
					activeTool: state.activeTool?.messageId === messageId ? null : state.activeTool
				}));
				toolClearTimeout = null;
			}, displayMs);
		}, updateDelay);
	};

	const markNeedsNewline = (messageId: string) => {
		update((state) => ({
			...state,
			messages: state.messages.map((msg) =>
				msg.id === messageId ? { ...msg, needsNewline: true } : msg
			)
		}));
	};

	return {
		clearToolTimers,
		setActiveTool,
		finalizeActiveTool,
		markNeedsNewline,
		getActiveToolStartTime,
		cleanup: () => {
			clearToolTimers();
		}
	};
}
