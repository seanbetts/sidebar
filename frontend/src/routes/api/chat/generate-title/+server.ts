/**
 * SvelteKit server route for generating conversation titles
 */
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

const API_URL = process.env.API_URL || 'http://skills-api:8001';
const BEARER_TOKEN = process.env.BEARER_TOKEN;

// POST /api/chat/generate-title - Generate title for conversation
export const POST: RequestHandler = async ({ request }) => {
	try {
		const body = await request.json();

		const response = await fetch(`${API_URL}/api/chat/generate-title`, {
			method: 'POST',
			headers: {
				Authorization: `Bearer ${BEARER_TOKEN}`,
				'Content-Type': 'application/json'
			},
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
