import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

const API_URL = process.env.API_URL || 'http://skills-api:8001';
const BEARER_TOKEN = process.env.BEARER_TOKEN || '';

export const POST: RequestHandler = async ({ fetch, url }) => {
  const query = url.searchParams.get('query') || '';
  const limit = url.searchParams.get('limit') || '50';

  try {
    const response = await fetch(
      `${API_URL}/api/notes/search?query=${encodeURIComponent(query)}&limit=${encodeURIComponent(limit)}`,
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
    console.error('Failed to search notes:', error);
    return json({ error: 'Failed to search notes' }, { status: 500 });
  }
};
