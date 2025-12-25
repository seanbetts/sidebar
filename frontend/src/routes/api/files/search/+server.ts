import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

const API_URL = process.env.API_URL || 'http://skills-api:8001';
const BEARER_TOKEN = process.env.BEARER_TOKEN || '';

export const POST: RequestHandler = async ({ fetch, url }) => {
  try {
    const basePath = url.searchParams.get('basePath') || 'documents';
    if (basePath === 'notes') {
      return json({ error: 'Notes are served from /api/notes' }, { status: 400 });
    }
    const query = url.searchParams.get('query') || '';
    const limit = url.searchParams.get('limit') || '50';

    const response = await fetch(
      `${API_URL}/api/files/search?basePath=${encodeURIComponent(basePath)}&query=${encodeURIComponent(query)}&limit=${encodeURIComponent(limit)}`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${BEARER_TOKEN}`
        }
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
