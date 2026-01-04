import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getApiUrl, buildAuthHeaders } from '$lib/server/api';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ locals, fetch, url }) => {
  try {
    const basePath = url.searchParams.get('basePath') || 'documents';
    if (basePath === 'notes') {
      return json({ error: 'Notes are served from /api/notes' }, { status: 400 });
    }

    const response = await fetch(`${API_URL}/api/v1/files/tree?basePath=${encodeURIComponent(basePath)}`, {
      headers: buildAuthHeaders(locals)
    });

    if (!response.ok) {
      throw new Error(`Backend API error: ${response.statusText}`);
    }

    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to fetch file tree:', error);
    return json({ error: 'Failed to load files' }, { status: 500 });
  }
};
