import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

const API_URL = process.env.API_URL || 'http://skills-api:8001';
const BEARER_TOKEN = process.env.BEARER_TOKEN || '';

export const GET: RequestHandler = async ({ fetch, params }) => {
  try {
    const response = await fetch(`${API_URL}/api/memories/${params.id}`, {
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
    console.error('Failed to load memory:', error);
    return json({ error: 'Failed to load memory' }, { status: 500 });
  }
};

export const PATCH: RequestHandler = async ({ request, fetch, params }) => {
  try {
    const body = await request.json();
    const response = await fetch(`${API_URL}/api/memories/${params.id}`, {
      method: 'PATCH',
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
    console.error('Failed to update memory:', error);
    return json({ error: 'Failed to update memory' }, { status: 500 });
  }
};

export const DELETE: RequestHandler = async ({ fetch, params }) => {
  try {
    const response = await fetch(`${API_URL}/api/memories/${params.id}`, {
      method: 'DELETE',
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
    console.error('Failed to delete memory:', error);
    return json({ error: 'Failed to delete memory' }, { status: 500 });
  }
};
