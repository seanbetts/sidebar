import { getApiUrl, buildAuthHeaders } from '$lib/server/api';
/**
 * SvelteKit server route for proxying conversations API requests to backend
 */
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

const API_URL = getApiUrl();

// GET /api/conversations - List conversations
export const GET: RequestHandler = async ({ locals }) => {
	try {
		const response = await fetch(`${API_URL}/api/v1/conversations/`, {
			method: 'GET',
			headers: buildAuthHeaders(locals)
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
export const POST: RequestHandler = async ({ locals, request }) => {
	try {
		const body = await request.json();

		const response = await fetch(`${API_URL}/api/v1/conversations/`, {
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
		console.error('POST conversations error:', err);
		if (err instanceof Error && 'status' in err) {
			throw err;
		}
		throw error(500, 'Internal server error');
	}
};
