import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getApiUrl, buildAuthHeaders } from '$lib/server/api';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ locals, url, fetch }) => {
  const query = (url.searchParams.get('query') || '').trim();
  if (!query) {
    return json({ error: 'query required' }, { status: 400 });
  }

  try {
    const response = await fetch(`${API_URL}/api/things/search?query=${encodeURIComponent(query)}`, {
      headers: buildAuthHeaders(locals)
    });

    if (!response.ok) {
      throw new Error(`Backend API error: ${response.statusText}`);
    }

    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to search Things tasks:', error);
    return json({ error: 'Failed to search Things tasks' }, { status: 500 });
  }
};
