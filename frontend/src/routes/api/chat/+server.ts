import { getApiUrl, buildAuthHeaders } from '$lib/server/api';
/**
 * SvelteKit server route for proxying chat SSE requests to backend
 */
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

const API_URL = getApiUrl();

export const POST: RequestHandler = async ({ locals, request }) => {
	try {
		const userAgent = request.headers.get('user-agent') || '';
		const {
			message,
			history,
			conversation_id,
			user_message_id,
			open_context,
			attachments,
			current_location,
			current_location_levels,
			current_weather,
			current_timezone
		} = await request.json();

		if (!message) {
			throw error(400, 'Message is required');
		}

		// Forward request to backend
		const response = await fetch(`${API_URL}/api/chat/stream`, {
			method: 'POST',
			headers: buildAuthHeaders(locals, {
				'Content-Type': 'application/json',
				...(userAgent ? { 'User-Agent': userAgent } : {})
			}),
			body: JSON.stringify({
				message,
				history,
				conversation_id,
				user_message_id,
				open_context,
				attachments,
				current_location,
				current_location_levels,
				current_weather,
				current_timezone
			})
		});

		if (!response.ok) {
			throw error(response.status, `Backend error: ${response.statusText}`);
		}

		// Stream the response back to client
		const stream = new ReadableStream({
			async start(controller) {
				try {
					const reader = response.body?.getReader();
					if (!reader) {
						if (controller.desiredSize !== null) {
							controller.close();
						}
						return;
					}

					const decoder = new TextDecoder();
					const encoder = new TextEncoder();
					const safeEnqueue = (data: string) => {
						if (controller.desiredSize === null) {
							return false;
						}
						controller.enqueue(encoder.encode(data));
						return true;
					};

					while (true) {
						const { done, value } = await reader.read();
						if (done) break;

						// Forward chunk to client
						const chunk = decoder.decode(value, { stream: true });
						if (!safeEnqueue(chunk)) {
							await reader.cancel();
							break;
						}
					}

					if (controller.desiredSize !== null) {
						controller.close();
					}
				} catch (err) {
					console.error('Stream error:', err);
					if (controller.desiredSize !== null) {
						controller.error(err);
					}
				}
			}
		});

		return new Response(stream, {
			headers: {
				'Content-Type': 'text/event-stream',
				'Cache-Control': 'no-cache',
				Connection: 'keep-alive'
			}
		});
	} catch (err) {
		console.error('Chat route error:', err);
		if (err instanceof Error && 'status' in err) {
			throw err;
		}
		throw error(500, 'Internal server error');
	}
};
