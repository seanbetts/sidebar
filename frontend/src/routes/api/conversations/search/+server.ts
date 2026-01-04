import { getApiUrl, buildAuthHeaders } from '$lib/server/api';
/**
 * SvelteKit server route for searching conversations
 */
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

const API_URL = getApiUrl();

// POST /api/conversations/search - Search conversations
export const POST: RequestHandler = async ({ locals, url }) => {
	try {
		const query = url.searchParams.get('query') || '';
		const limit = url.searchParams.get('limit') || '10';

		const response = await fetch(
			`${API_URL}/api/v1/conversations/search?query=${encodeURIComponent(query)}&limit=${limit}`,
			{
				method: 'POST',
				headers: buildAuthHeaders(locals)
			}
		);

		if (!response.ok) {
			throw error(response.status, `Backend error: ${response.statusText}`);
		}

		const data = await response.json();
		return new Response(JSON.stringify(data), {
			headers: { 'Content-Type': 'application/json' }
		});
	} catch (err) {
		console.error('POST search error:', err);
		if (err instanceof Error && 'status' in err) {
			throw err;
		}
		throw error(500, 'Internal server error');
	}
};
