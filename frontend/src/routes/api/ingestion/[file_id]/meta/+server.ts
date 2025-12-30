import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { buildAuthHeaders, getApiUrl } from '$lib/server/api';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ locals, params, fetch }) => {
  try {
    const response = await fetch(`${API_URL}/api/ingestion/${params.file_id}/meta`, {
      headers: buildAuthHeaders(locals)
    });
    if (!response.ok) {
      throw new Error(`Backend API error: ${response.statusText}`);
    }
    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to get ingestion metadata:', error);
    return json({ error: 'Failed to get ingestion metadata' }, { status: 500 });
  }
};
