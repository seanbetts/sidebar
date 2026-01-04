import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { buildAuthHeaders, getApiUrl } from '$lib/server/api';

const API_URL = getApiUrl();

export const PATCH: RequestHandler = async ({ locals, params, request, fetch }) => {
  try {
    const body = await request.json();
    const response = await fetch(`${API_URL}/api/v1/ingestion/${params.file_id}/pin`, {
      method: 'PATCH',
      headers: {
        ...buildAuthHeaders(locals),
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(body)
    });
    if (!response.ok) {
      const detail = await response.text();
      throw new Error(detail || response.statusText);
    }
    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to update ingestion pin:', error);
    return json({ error: 'Failed to update pinned state' }, { status: 500 });
  }
};
