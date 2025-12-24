/**
 * SvelteKit server route for proxying Places autocomplete requests to backend
 */
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

const API_URL = process.env.API_URL || 'http://skills-api:8001';
const BEARER_TOKEN = process.env.BEARER_TOKEN;

export const GET: RequestHandler = async ({ url }) => {
	try {
		const input = url.searchParams.get('input');
		if (!input) {
			throw error(400, 'input is required');
		}

		const response = await fetch(`${API_URL}/api/places/autocomplete?input=${encodeURIComponent(input)}`, {
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
		console.error('Places autocomplete error:', err);
		if (err instanceof Error && 'status' in err) {
			throw err;
		}
		throw error(500, 'Internal server error');
	}
};
