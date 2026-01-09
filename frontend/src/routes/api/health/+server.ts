import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getApiUrl } from '$lib/server/api';
import { logError } from '$lib/utils/errorHandling';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ fetch }) => {
	try {
		// Use legacy `/api/health` because backend auth middleware allows it without a JWT.
		// `/api/v1/health` is currently protected and will return 401.
		const response = await fetch(`${API_URL}/api/health`);
		const data = await response.json().catch(() => ({}));

		if (!response.ok) {
			return json(data, { status: response.status });
		}

		return json(data);
	} catch (error) {
		logError('Failed to check health', error, { scope: 'api.health' });
		return json({ status: 'unhealthy' }, { status: 503 });
	}
};
