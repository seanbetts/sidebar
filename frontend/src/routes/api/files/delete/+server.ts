import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

const API_URL = process.env.API_URL || 'http://skills-api:8001';
const BEARER_TOKEN = process.env.BEARER_TOKEN || '';

export const POST: RequestHandler = async ({ request, fetch }) => {
  try {
    const body = await request.json();
    if (body?.basePath === 'notes') {
      return json({ error: 'Notes are served from /api/notes' }, { status: 400 });
    }

    const response = await fetch(`${API_URL}/api/files/delete`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${BEARER_TOKEN}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(body)
    });

    if (!response.ok) {
      throw new Error(`Backend API error: ${response.statusText}`);
    }

    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to delete file/folder:', error);
    return json({ error: 'Failed to delete' }, { status: 500 });
  }
};
