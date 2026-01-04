import { getApiUrl, buildAuthHeaders } from '$lib/server/api';
/**
 * SvelteKit server route for proxying profile image uploads to backend
 */
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

const API_URL = getApiUrl();

export const config = {
	csrf: false
};

export const GET: RequestHandler = async ({ locals, request, fetch }) => {
	try {
		const response = await fetch(`${API_URL}/api/v1/settings/profile-image`, {
			headers: buildAuthHeaders(locals)
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

export const POST: RequestHandler = async ({ locals, request, fetch }) => {
	try {
		const contentType = request.headers.get('content-type') || '';
		const filename = request.headers.get('x-filename') || 'profile-image';

		let response: Response;
		if (contentType.startsWith('image/') || contentType === 'application/octet-stream') {
			const buffer = await request.arrayBuffer();
			response = await fetch(`${API_URL}/api/v1/settings/profile-image`, {
				method: 'POST',
				headers: buildAuthHeaders(locals, {
					'Content-Type': contentType || 'application/octet-stream',
					'X-Filename': filename
				}),
				body: buffer
			});
		} else {
			const formData = await request.formData();
			response = await fetch(`${API_URL}/api/v1/settings/profile-image`, {
				method: 'POST',
				headers: buildAuthHeaders(locals, {
					'X-Filename': filename
				}),
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

export const DELETE: RequestHandler = async ({ locals, request, fetch }) => {
	try {
		const response = await fetch(`${API_URL}/api/v1/settings/profile-image`, {
			method: 'DELETE',
			headers: buildAuthHeaders(locals)
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
