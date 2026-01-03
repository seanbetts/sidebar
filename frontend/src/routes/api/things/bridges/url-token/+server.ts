import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { buildAuthHeaders, getApiUrl } from '$lib/server/api';

const API_URL = getApiUrl();

export const POST: RequestHandler = async ({ locals, fetch, request }) => {
  try {
    const body = await request.json();
    const response = await fetch(`${API_URL}/api/things/bridges/url-token`, {
      method: 'POST',
      headers: {
        ...buildAuthHeaders(locals),
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(body)
    });
    const data = await response.json();
    return json(data, { status: response.status });
  } catch (error) {
    console.error('Failed to save Things URL token:', error);
    return json({ error: 'Failed to save Things URL token' }, { status: 500 });
  }
};
