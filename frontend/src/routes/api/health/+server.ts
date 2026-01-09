import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getApiUrl } from '$lib/server/api';
import { logError } from '$lib/utils/errorHandling';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ fetch }) => {
	try {
		const response = await fetch(`${API_URL}/api/v1/health`);
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
