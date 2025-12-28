import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getApiUrl, buildAuthHeaders } from '$lib/server/api';

const API_URL = getApiUrl();

export const POST: RequestHandler = async ({ locals, fetch, url }) => {
  const query = url.searchParams.get('query') || '';
  const limit = url.searchParams.get('limit') || '50';

  try {
    const response = await fetch(
      `${API_URL}/api/notes/search?query=${encodeURIComponent(query)}&limit=${encodeURIComponent(limit)}`,
      {
        method: 'POST',
        headers: buildAuthHeaders(locals)
      }
    );

    if (!response.ok) {
      throw new Error(`Backend API error: ${response.statusText}`);
    }

    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to search notes:', error);
    return json({ error: 'Failed to search notes' }, { status: 500 });
  }
};
