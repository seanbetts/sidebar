import { getApiUrl, buildAuthHeaders } from '$lib/server/api';
/**
 * SvelteKit server route for individual conversation operations
 */
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

const API_URL = getApiUrl();

// GET /api/conversations/[id] - Get conversation with messages
export const GET: RequestHandler = async ({ locals, params }) => {
	try {
		const response = await fetch(`${API_URL}/api/v1/conversations/${params.id}`, {
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
		console.error('GET conversation error:', err);
		if (err instanceof Error && 'status' in err) {
			throw err;
		}
		throw error(500, 'Internal server error');
	}
};

// PUT /api/conversations/[id] - Update conversation
export const PUT: RequestHandler = async ({ locals, params, request }) => {
	try {
		const body = await request.json();

		const response = await fetch(`${API_URL}/api/v1/conversations/${params.id}`, {
			method: 'PUT',
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
		console.error('PUT conversation error:', err);
		if (err instanceof Error && 'status' in err) {
			throw err;
		}
		throw error(500, 'Internal server error');
	}
};

// DELETE /api/conversations/[id] - Archive conversation
export const DELETE: RequestHandler = async ({ locals, params }) => {
	try {
		const response = await fetch(`${API_URL}/api/v1/conversations/${params.id}`, {
			method: 'DELETE',
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
		console.error('DELETE conversation error:', err);
		if (err instanceof Error && 'status' in err) {
			throw err;
		}
		throw error(500, 'Internal server error');
	}
};
