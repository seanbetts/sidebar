import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

const API_URL = process.env.API_URL || 'http://skills-api:8001';
const BEARER_TOKEN = process.env.BEARER_TOKEN || '';

export const GET: RequestHandler = async ({ fetch, url }) => {
  try {
    const basePath = url.searchParams.get('basePath') || 'notes';
    const path = url.searchParams.get('path') || '';

    const response = await fetch(
      `${API_URL}/api/files/content?basePath=${basePath}&path=${encodeURIComponent(path)}`,
      {
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
    console.error('Failed to load file:', error);
    return json({ error: 'Failed to load file' }, { status: 500 });
  }
};

export const POST: RequestHandler = async ({ request, fetch }) => {
  try {
    const body = await request.json();

    const response = await fetch(`${API_URL}/api/files/content`, {
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
    console.error('Failed to save file:', error);
    return json({ error: 'Failed to save file' }, { status: 500 });
  }
};
