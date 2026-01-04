import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getApiUrl, buildAuthHeaders } from '$lib/server/api';

const API_URL = getApiUrl();

export const PATCH: RequestHandler = async ({ locals, request, fetch, params }) => {
  try {
    const body = await request.json();
    const response = await fetch(`${API_URL}/api/v1/websites/${params.id}/pin`, {
      method: 'PATCH',
      headers: buildAuthHeaders(locals, {
        'Content-Type': 'application/json'
      }),
      body: JSON.stringify(body)
    });

    if (!response.ok) {
      throw new Error(`Backend API error: ${response.statusText}`);
    }

    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to pin website:', error);
    return json({ error: 'Failed to pin website' }, { status: 500 });
  }
};
