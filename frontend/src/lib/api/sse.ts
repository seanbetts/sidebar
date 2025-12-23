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
}

export class SSEClient {
	private eventSource: EventSource | null = null;

	/**
	 * Connect to SSE endpoint and stream chat response
	 */
	async connect(message: string, callbacks: SSECallbacks): Promise<void> {
		try {
			// Send message to backend via fetch POST to get SSE stream
			const response = await fetch('/api/chat', {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json'
				},
				body: JSON.stringify({ message })
			});

			if (!response.ok) {
				throw new Error(`HTTP ${response.status}: ${response.statusText}`);
			}

			if (!response.body) {
				throw new Error('No response body');
			}

			// Parse SSE stream manually
			const reader = response.body.getReader();
			const decoder = new TextDecoder();
			let buffer = '';

			while (true) {
				const { done, value } = await reader.read();
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
			console.error('SSE connection error:', error);
			callbacks.onError?.(error instanceof Error ? error.message : String(error));
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

			default:
				console.warn('Unknown SSE event type:', eventType);
		}
	}

	/**
	 * Disconnect from SSE stream
	 */
	disconnect(): void {
		if (this.eventSource) {
			this.eventSource.close();
			this.eventSource = null;
		}
	}
}
