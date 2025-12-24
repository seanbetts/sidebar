import type { RequestHandler } from './$types';

const API_URL = process.env.API_URL || 'http://skills-api:8001';
const BEARER_TOKEN = process.env.BEARER_TOKEN || '';

export const GET: RequestHandler = async ({ fetch }) => {
	const response = await fetch(`${API_URL}/api/skills`, {
		headers: {
			Authorization: `Bearer ${BEARER_TOKEN}`
		}
	});

	const body = await response.text();
	return new Response(body, {
		status: response.status,
		headers: { 'Content-Type': response.headers.get('Content-Type') || 'application/json' }
	});
};
