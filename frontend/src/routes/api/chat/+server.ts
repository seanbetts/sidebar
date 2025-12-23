/**
 * SvelteKit server route for proxying chat SSE requests to backend
 */
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

const API_URL = process.env.API_URL || 'http://skills-api:8001';
const BEARER_TOKEN = process.env.BEARER_TOKEN;

export const POST: RequestHandler = async ({ request }) => {
	try {
		const { message, history, conversation_id, user_message_id } = await request.json();

		if (!message) {
			throw error(400, 'Message is required');
		}

		// Forward request to backend
		const response = await fetch(`${API_URL}/api/chat/stream`, {
			method: 'POST',
			headers: {
				Authorization: `Bearer ${BEARER_TOKEN}`,
				'Content-Type': 'application/json'
			},
			body: JSON.stringify({
				message,
				history,
				conversation_id,
				user_message_id
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
						controller.close();
						return;
					}

					const decoder = new TextDecoder();

					while (true) {
						const { done, value } = await reader.read();
						if (done) break;

						// Forward chunk to client
						const chunk = decoder.decode(value, { stream: true });
						controller.enqueue(new TextEncoder().encode(chunk));
					}

					controller.close();
				} catch (err) {
					console.error('Stream error:', err);
					controller.error(err);
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
