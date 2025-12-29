import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getApiUrl } from '$lib/server/api';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ fetch }) => {
  try {
    const response = await fetch(`${API_URL}/api/health`);
    const data = await response.json().catch(() => ({}));

    if (!response.ok) {
      return json(data, { status: response.status });
    }

    return json(data);
  } catch (error) {
    console.error('Failed to check health:', error);
    return json({ status: 'unhealthy' }, { status: 503 });
  }
};
