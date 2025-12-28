import { getApiUrl, buildAuthHeaders } from '$lib/server/api';
/**
 * SvelteKit server route for proxying settings API requests to backend
 */
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ locals }) => {
	try {
		const response = await fetch(`${API_URL}/api/settings`, {
			headers: buildAuthHeaders(locals)
		});

		if (!response.ok) {
			throw error(response.status, `Backend error: ${response.statusText}`);
		}

		return new Response(await response.text(), {
			headers: { 'Content-Type': 'application/json' }
		});
	} catch (err) {
		console.error('Settings GET error:', err);
		if (err instanceof Error && 'status' in err) {
			throw err;
		}
		throw error(500, 'Internal server error');
	}
};

export const PATCH: RequestHandler = async ({ locals, request }) => {
	try {
		const payload = await request.json();

		const response = await fetch(`${API_URL}/api/settings`, {
			method: 'PATCH',
			headers: buildAuthHeaders(locals, {
				'Content-Type': 'application/json'
			}),
			body: JSON.stringify(payload)
		});

		if (!response.ok) {
			throw error(response.status, `Backend error: ${response.statusText}`);
		}

		return new Response(await response.text(), {
			headers: { 'Content-Type': 'application/json' }
		});
	} catch (err) {
		console.error('Settings PATCH error:', err);
		if (err instanceof Error && 'status' in err) {
			throw err;
		}
		throw error(500, 'Internal server error');
	}
};
