import type { RequestHandler } from './$types';
import { getApiUrl, buildAuthHeaders } from '$lib/server/api';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ locals, fetch }) => {
	const response = await fetch(`${API_URL}/api/v1/skills`, {
		headers: buildAuthHeaders(locals)
	});

	const body = await response.text();
	return new Response(body, {
		status: response.status,
		headers: { 'Content-Type': response.headers.get('Content-Type') || 'application/json' }
	});
};
