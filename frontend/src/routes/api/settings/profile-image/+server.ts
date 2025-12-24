/**
 * SvelteKit server route for proxying profile image uploads to backend
 */
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

const API_URL = process.env.API_URL || 'http://skills-api:8001';
const BEARER_TOKEN = process.env.BEARER_TOKEN;

export const config = {
	csrf: false
};

function resolveBearerToken(): string {
	const token = (BEARER_TOKEN || '').trim();
	if (!token || token === 'undefined' || token === 'null') {
		throw error(500, 'BEARER_TOKEN not configured');
	}
	return token;
}

export const GET: RequestHandler = async ({ request, fetch }) => {
	try {
		const authHeader = request.headers.get('authorization');
		const bearerToken = resolveBearerToken();
		const response = await fetch(`${API_URL}/api/settings/profile-image`, {
			headers: {
				Authorization: authHeader || `Bearer ${bearerToken}`
			}
		});

		if (!response.ok) {
			const body = await response.text();
			return new Response(body, { status: response.status });
		}

		return new Response(response.body, {
			headers: response.headers
		});
	} catch (err) {
		console.error('Profile image GET error:', err);
		if (err instanceof Error && 'status' in err) {
			throw err;
		}
		throw error(500, 'Internal server error');
	}
};

export const POST: RequestHandler = async ({ request, fetch }) => {
	try {
		const contentType = request.headers.get('content-type') || '';
		const authHeader = request.headers.get('authorization');
		const bearerToken = resolveBearerToken();
		const filename = request.headers.get('x-filename') || 'profile-image';

		let response: Response;
		if (contentType.startsWith('image/') || contentType === 'application/octet-stream') {
			const buffer = await request.arrayBuffer();
			response = await fetch(`${API_URL}/api/settings/profile-image`, {
				method: 'POST',
				headers: {
					Authorization: authHeader || `Bearer ${bearerToken}`,
					'Content-Type': contentType || 'application/octet-stream',
					'X-Filename': filename
				},
				body: buffer
			});
		} else {
			const formData = await request.formData();
			response = await fetch(`${API_URL}/api/settings/profile-image`, {
				method: 'POST',
				headers: {
					Authorization: authHeader || `Bearer ${bearerToken}`,
					'X-Filename': filename
				},
				body: formData
			});
		}

		if (!response.ok) {
			const body = await response.text();
			return new Response(body, { status: response.status });
		}

		return new Response(await response.text(), {
			headers: { 'Content-Type': 'application/json' }
		});
	} catch (err) {
		console.error('Profile image POST error:', err);
		if (err instanceof Error && 'status' in err) {
			throw err;
		}
		throw error(500, 'Internal server error');
	}
};

export const DELETE: RequestHandler = async ({ request, fetch }) => {
	try {
		const authHeader = request.headers.get('authorization');
		const bearerToken = resolveBearerToken();

		const response = await fetch(`${API_URL}/api/settings/profile-image`, {
			method: 'DELETE',
			headers: {
				Authorization: authHeader || `Bearer ${bearerToken}`
			}
		});

		if (!response.ok) {
			const body = await response.text();
			return new Response(body, { status: response.status });
		}

		return new Response(await response.text(), {
			headers: { 'Content-Type': 'application/json' }
		});
	} catch (err) {
		console.error('Profile image DELETE error:', err);
		if (err instanceof Error && 'status' in err) {
			throw err;
		}
		throw error(500, 'Internal server error');
	}
};
