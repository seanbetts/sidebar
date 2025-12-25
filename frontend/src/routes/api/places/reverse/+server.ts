/**
 * SvelteKit server route for proxying Places reverse geocode requests to backend
 */
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

const API_URL = process.env.API_URL || 'http://skills-api:8001';
const BEARER_TOKEN = process.env.BEARER_TOKEN;

export const GET: RequestHandler = async ({ url }) => {
	try {
		const lat = url.searchParams.get('lat');
		const lng = url.searchParams.get('lng');
		if (!lat || !lng) {
			throw error(400, 'lat and lng are required');
		}

		const response = await fetch(
			`${API_URL}/api/places/reverse?lat=${encodeURIComponent(lat)}&lng=${encodeURIComponent(lng)}`,
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
			headers: { 'Content-Type': 'application/json' }
		});
	} catch (err) {
		console.error('Places reverse geocode error:', err);
		if (typeof err === 'object' && err && 'status' in err) {
			throw err;
		}
		throw error(500, 'Internal server error');
	}
};
