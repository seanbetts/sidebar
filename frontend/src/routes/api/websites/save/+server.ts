import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getApiUrl, buildAuthHeaders } from '$lib/server/api';

const API_URL = getApiUrl();

export const POST: RequestHandler = async ({ locals, request, fetch }) => {
  try {
    const body = await request.json();
    const response = await fetch(`${API_URL}/api/websites/save`, {
      method: 'POST',
      headers: buildAuthHeaders(locals, {
        'Content-Type': 'application/json'
      }),
      body: JSON.stringify(body)
    });

    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      const errorDetail = data?.detail ?? data?.error ?? response.statusText;
      return json({ error: errorDetail }, { status: response.status });
    }

    return json(data);
  } catch (error) {
    console.error('Failed to save website:', error);
    return json({ error: 'Failed to save website' }, { status: 500 });
  }
};
