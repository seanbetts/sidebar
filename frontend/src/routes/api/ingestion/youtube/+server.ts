import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { buildAuthHeaders, getApiUrl } from '$lib/server/api';

const API_URL = getApiUrl();

export const POST: RequestHandler = async ({ locals, request, fetch }) => {
  try {
    const payload = await request.json();
    const response = await fetch(`${API_URL}/api/v1/ingestion/youtube`, {
      method: 'POST',
      headers: buildAuthHeaders(locals, { 'Content-Type': 'application/json' }),
      body: JSON.stringify(payload)
    });
    if (!response.ok) {
      const detail = await response.text();
      return json(
        { detail: detail || response.statusText || 'Failed to add YouTube video' },
        { status: response.status }
      );
    }
    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to add YouTube video:', error);
    return json({ error: 'Failed to add YouTube video' }, { status: 500 });
  }
};
