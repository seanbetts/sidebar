import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

const API_URL = process.env.API_URL || 'http://skills-api:8001';
const BEARER_TOKEN = process.env.BEARER_TOKEN || '';

export const GET: RequestHandler = async ({ fetch, url }) => {
  try {
    const basePath = url.searchParams.get('basePath') || 'documents';

    const response = await fetch(`${API_URL}/api/files/tree?basePath=${basePath}`, {
      headers: {
        'Authorization': `Bearer ${BEARER_TOKEN}`
      }
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
