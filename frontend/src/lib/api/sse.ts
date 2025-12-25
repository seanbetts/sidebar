/**
 * SSE (Server-Sent Events) client for streaming chat
 */
import type { SSEEvent } from '$lib/types/chat';

export interface SSECallbacks {
	onToken?: (content: string) => void;
	onToolCall?: (event: any) => void;
	onToolResult?: (event: any) => void;
	onComplete?: () => void;
	onError?: (error: string) => void;
	onNoteCreated?: (data: { id?: string; title?: string; folder?: string }) => void;
	onNoteUpdated?: (data: { id?: string; title?: string }) => void;
	onWebsiteSaved?: (data: { id?: string; title?: string; url?: string }) => void;
	onNoteDeleted?: (data: { id?: string }) => void;
	onWebsiteDeleted?: (data: { id?: string }) => void;
	onThemeSet?: (data: { theme?: string }) => void;
	onScratchpadUpdated?: () => void;
	onScratchpadCleared?: () => void;
	onPromptPreview?: (data: { system_prompt?: string; first_message_prompt?: string }) => void;
	onServerToolStart?: (data: { name?: string; input?: Record<string, any> }) => void;
	onServerToolEnd?: (data: { name?: string; error?: string | null }) => void;
}

export class SSEClient {
	private abortController: AbortController | null = null;
	private reader: ReadableStreamDefaultReader<Uint8Array> | null = null;

	/**
	 * Connect to SSE endpoint and stream chat response
	 */
	async connect(
		payload: {
			message: string;
			conversationId?: string;
			userMessageId?: string;
			openContext?: any;
			currentLocation?: string;
			currentLocationLevels?: Record<string, string>;
			currentWeather?: Record<string, unknown>;
			currentTimezone?: string;
		},
		callbacks: SSECallbacks
	): Promise<void> {
		// Create abort controller for this connection
		this.abortController = new AbortController();

		try {
			// Send message to backend via fetch POST to get SSE stream
			const response = await fetch('/api/chat', {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json'
				},
				body: JSON.stringify({
					message: payload.message,
					conversation_id: payload.conversationId,
					user_message_id: payload.userMessageId,
					open_context: payload.openContext,
					current_location: payload.currentLocation,
					current_location_levels: payload.currentLocationLevels,
					current_weather: payload.currentWeather,
					current_timezone: payload.currentTimezone
				}),
				signal: this.abortController.signal
			});

			if (!response.ok) {
				throw new Error(`HTTP ${response.status}: ${response.statusText}`);
			}

			if (!response.body) {
				throw new Error('No response body');
			}

			// Parse SSE stream manually
			this.reader = response.body.getReader();
			const decoder = new TextDecoder();
			let buffer = '';

			while (true) {
				const { done, value } = await this.reader.read();
				if (done) break;

				// Accumulate chunks
				buffer += decoder.decode(value, { stream: true });

				// Process complete events (separated by \n\n)
				const events = buffer.split('\n\n');
				buffer = events.pop() || ''; // Keep incomplete event in buffer

				for (const eventText of events) {
					if (!eventText.trim()) continue;

					// Parse SSE format: "event: type\ndata: json"
					const lines = eventText.split('\n');
					let eventType = 'message';
					let eventData = '';

					for (const line of lines) {
						if (line.startsWith('event:')) {
							eventType = line.substring(6).trim();
						} else if (line.startsWith('data:')) {
							eventData = line.substring(5).trim();
						}
					}

					if (!eventData) continue;

					try {
						const data = JSON.parse(eventData);
						this.handleEvent(eventType, data, callbacks);
					} catch (e) {
						console.error('Failed to parse SSE data:', eventData, e);
					}
				}
			}
		} catch (error) {
			// Don't report error if connection was intentionally aborted
			if (error instanceof Error && error.name === 'AbortError') {
				console.log('SSE connection aborted');
				return;
			}
			console.error('SSE connection error:', error);
			callbacks.onError?.(error instanceof Error ? error.message : String(error));
		} finally {
			// Clean up references
			this.reader = null;
			this.abortController = null;
		}
	}

	private handleEvent(eventType: string, data: any, callbacks: SSECallbacks): void {
		switch (eventType) {
			case 'token':
				callbacks.onToken?.(data.content);
				break;

			case 'tool_call':
				callbacks.onToolCall?.(data);
				break;

			case 'tool_result':
				callbacks.onToolResult?.(data);
				break;

			case 'complete':
				callbacks.onComplete?.();
				break;

			case 'error':
				callbacks.onError?.(data.error || 'Unknown error');
				break;

			case 'note_created':
				callbacks.onNoteCreated?.(data);
				break;

			case 'note_updated':
				callbacks.onNoteUpdated?.(data);
				break;

			case 'website_saved':
				callbacks.onWebsiteSaved?.(data);
				break;

			case 'note_deleted':
				callbacks.onNoteDeleted?.(data);
				break;

			case 'website_deleted':
				callbacks.onWebsiteDeleted?.(data);
				break;

			case 'ui_theme_set':
				callbacks.onThemeSet?.(data);
				break;

			case 'scratchpad_updated':
				callbacks.onScratchpadUpdated?.();
				break;

			case 'scratchpad_cleared':
				callbacks.onScratchpadCleared?.();
				break;

			case 'prompt_preview':
				callbacks.onPromptPreview?.(data);
				break;
			case 'server_tool_start':
				callbacks.onServerToolStart?.(data);
				break;
			case 'server_tool_end':
				callbacks.onServerToolEnd?.(data);
				break;

			default:
				console.warn('Unknown SSE event type:', eventType);
		}
	}

	/**
	 * Disconnect from SSE stream
	 */
	disconnect(): void {
		// Abort the fetch request
		if (this.abortController) {
			this.abortController.abort();
			this.abortController = null;
		}

		// Cancel the reader
		if (this.reader) {
			this.reader.cancel().catch(() => {
				// Ignore errors from cancelling already-closed reader
			});
			this.reader = null;
		}
	}
}
