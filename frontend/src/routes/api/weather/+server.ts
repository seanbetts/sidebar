/**
 * SvelteKit server route for proxying weather requests to backend
 */
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

const API_URL = process.env.API_URL || 'http://skills-api:8001';
const BEARER_TOKEN = process.env.BEARER_TOKEN;

export const GET: RequestHandler = async ({ url }) => {
	try {
		const lat = url.searchParams.get('lat');
		const lon = url.searchParams.get('lon');
		if (!lat || !lon) {
			throw error(400, 'lat and lon are required');
		}

		const response = await fetch(
			`${API_URL}/api/weather?lat=${encodeURIComponent(lat)}&lon=${encodeURIComponent(lon)}`,
			{
				headers: {
					Authorization: `Bearer ${BEARER_TOKEN}`
				}
			}
		);

		if (!response.ok) {
			throw error(response.status, `Backend error: ${response.statusText}`);
		}

		return new Response(await response.text(), {
			headers: {
				'Content-Type': 'application/json',
				'Cache-Control': 'max-age=1800'
			}
		});
	} catch (err) {
		console.error('Weather proxy error:', err);
		if (typeof err === 'object' && err && 'status' in err) {
			throw err;
		}
		throw error(500, 'Internal server error');
	}
};
