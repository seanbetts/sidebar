import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getApiUrl, buildAuthHeaders } from '$lib/server/api';

const API_URL = getApiUrl();

export const POST: RequestHandler = async ({ locals, fetch, url }) => {
  try {
    const basePath = url.searchParams.get('basePath') || 'documents';
    if (basePath === 'notes') {
      return json({ error: 'Notes are served from /api/notes' }, { status: 400 });
    }
    const query = url.searchParams.get('query') || '';
    const limit = url.searchParams.get('limit') || '50';

    const response = await fetch(
      `${API_URL}/api/v1/files/search?basePath=${encodeURIComponent(basePath)}&query=${encodeURIComponent(query)}&limit=${encodeURIComponent(limit)}`,
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
    console.error('Failed to search files:', error);
    return json({ error: 'Failed to search files' }, { status: 500 });
  }
};
