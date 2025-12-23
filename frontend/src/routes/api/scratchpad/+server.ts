import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

const API_URL = process.env.API_URL || 'http://skills-api:8001';
const BEARER_TOKEN = process.env.BEARER_TOKEN || '';

export const GET: RequestHandler = async ({ fetch }) => {
  try {
    const response = await fetch(`${API_URL}/api/scratchpad`, {
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
    console.error('Failed to load scratchpad:', error);
    return json({ error: 'Failed to load scratchpad' }, { status: 500 });
  }
};

export const POST: RequestHandler = async ({ request, fetch }) => {
  try {
    const body = await request.json();
    const response = await fetch(`${API_URL}/api/scratchpad`, {
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
    console.error('Failed to save scratchpad:', error);
    return json({ error: 'Failed to save scratchpad' }, { status: 500 });
  }
};

export const DELETE: RequestHandler = async ({ fetch }) => {
  try {
    const response = await fetch(`${API_URL}/api/scratchpad`, {
      method: 'DELETE',
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
    console.error('Failed to clear scratchpad:', error);
    return json({ error: 'Failed to clear scratchpad' }, { status: 500 });
  }
};
