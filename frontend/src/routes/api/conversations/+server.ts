/**
 * SvelteKit server route for proxying conversations API requests to backend
 */
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

const API_URL = process.env.API_URL || 'http://skills-api:8001';
const BEARER_TOKEN = process.env.BEARER_TOKEN;

// GET /api/conversations - List conversations
export const GET: RequestHandler = async () => {
	try {
		const response = await fetch(`${API_URL}/api/conversations/`, {
			method: 'GET',
			headers: {
				Authorization: `Bearer ${BEARER_TOKEN}`
			}
		});

		if (!response.ok) {
			throw error(response.status, `Backend error: ${response.statusText}`);
		}

		const data = await response.json();
		return new Response(JSON.stringify(data), {
			headers: { 'Content-Type': 'application/json' }
		});
	} catch (err) {
		console.error('GET conversations error:', err);
		if (err instanceof Error && 'status' in err) {
			throw err;
		}
		throw error(500, 'Internal server error');
	}
};

// POST /api/conversations - Create conversation
export const POST: RequestHandler = async ({ request }) => {
	try {
		const body = await request.json();

		const response = await fetch(`${API_URL}/api/conversations/`, {
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
		console.error('POST conversations error:', err);
		if (err instanceof Error && 'status' in err) {
			throw err;
		}
		throw error(500, 'Internal server error');
	}
};
