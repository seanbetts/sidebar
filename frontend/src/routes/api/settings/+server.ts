/**
 * SvelteKit server route for proxying settings API requests to backend
 */
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

const API_URL = process.env.API_URL || 'http://skills-api:8001';
const BEARER_TOKEN = process.env.BEARER_TOKEN;

export const GET: RequestHandler = async () => {
	try {
		const response = await fetch(`${API_URL}/api/settings`, {
			headers: {
				Authorization: `Bearer ${BEARER_TOKEN}`
			}
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

export const PATCH: RequestHandler = async ({ request }) => {
	try {
		const payload = await request.json();

		const response = await fetch(`${API_URL}/api/settings`, {
			method: 'PATCH',
			headers: {
				Authorization: `Bearer ${BEARER_TOKEN}`,
				'Content-Type': 'application/json'
			},
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
