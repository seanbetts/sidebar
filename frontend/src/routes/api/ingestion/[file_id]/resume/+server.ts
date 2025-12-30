import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { buildAuthHeaders, getApiUrl } from '$lib/server/api';

const API_URL = getApiUrl();

export const POST: RequestHandler = async ({ locals, params, fetch }) => {
  try {
    const response = await fetch(`${API_URL}/api/ingestion/${params.file_id}/resume`, {
      method: 'POST',
      headers: buildAuthHeaders(locals)
    });
    if (!response.ok) {
      const detail = await response.text();
      throw new Error(detail || response.statusText);
    }
    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to resume ingestion:', error);
    return json({ error: 'Failed to resume ingestion' }, { status: 500 });
  }
};
