import { getApiUrl, buildAuthHeaders } from '$lib/server/api';
/**
 * SvelteKit server route for generating conversation titles
 */
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

const API_URL = getApiUrl();

// POST /api/chat/generate-title - Generate title for conversation
export const POST: RequestHandler = async ({ locals, request }) => {
	try {
		const body = await request.json();

		const response = await fetch(`${API_URL}/api/chat/generate-title`, {
			method: 'POST',
			headers: buildAuthHeaders(locals, {
				'Content-Type': 'application/json'
			}),
			body: JSON.stringify(body)
		});

		if (!response.ok) {
			throw error(response.status, `Backend error: ${response.statusText}`);
		}

		const data = await response.json();
		return new Response(JSON.stringify(data), {
			headers: { 'Content-Type': 'application/json' }
		});
	} catch (err) {
		console.error('POST generate-title error:', err);
		if (err instanceof Error && 'status' in err) {
			throw err;
		}
		throw error(500, 'Internal server error');
	}
};
