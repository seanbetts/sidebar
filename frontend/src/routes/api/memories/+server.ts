import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

const API_URL = process.env.API_URL || 'http://skills-api:8001';
const BEARER_TOKEN = process.env.BEARER_TOKEN || '';

export const GET: RequestHandler = async ({ fetch }) => {
  try {
    const response = await fetch(`${API_URL}/api/memories`, {
      headers: {
        Authorization: `Bearer ${BEARER_TOKEN}`
      }
    });

    if (!response.ok) {
      throw new Error(`Backend API error: ${response.statusText}`);
    }

    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to load memories:', error);
    return json({ error: 'Failed to load memories' }, { status: 500 });
  }
};

export const POST: RequestHandler = async ({ request, fetch }) => {
  try {
    const body = await request.json();
    const response = await fetch(`${API_URL}/api/memories`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${BEARER_TOKEN}`,
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
    console.error('Failed to create memory:', error);
    return json({ error: 'Failed to create memory' }, { status: 500 });
  }
};
