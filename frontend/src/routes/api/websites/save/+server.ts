import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

const API_URL = process.env.API_URL || 'http://skills-api:8001';
const BEARER_TOKEN = process.env.BEARER_TOKEN || '';

export const POST: RequestHandler = async ({ request, fetch }) => {
  try {
    const body = await request.json();
    const response = await fetch(`${API_URL}/api/websites/save`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${BEARER_TOKEN}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(body)
    });

    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      const errorDetail = data?.detail ?? data?.error ?? response.statusText;
      return json({ error: errorDetail }, { status: response.status });
    }

    return json(data);
  } catch (error) {
    console.error('Failed to save website:', error);
    return json({ error: 'Failed to save website' }, { status: 500 });
  }
};
