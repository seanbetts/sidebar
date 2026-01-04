import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getApiUrl, buildAuthHeaders } from '$lib/server/api';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ locals, fetch }) => {
  try {
    const response = await fetch(`${API_URL}/api/v1/memories`, {
      headers: buildAuthHeaders(locals)
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

export const POST: RequestHandler = async ({ locals, request, fetch }) => {
  try {
    const body = await request.json();
    const response = await fetch(`${API_URL}/api/v1/memories`, {
      method: 'POST',
      headers: buildAuthHeaders(locals, {
        'Content-Type': 'application/json'
      }),
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
