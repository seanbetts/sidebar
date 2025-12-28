import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getApiUrl, buildAuthHeaders } from '$lib/server/api';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ locals, fetch }) => {
  try {
    const response = await fetch(`${API_URL}/api/scratchpad`, {
      headers: buildAuthHeaders(locals)
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

export const POST: RequestHandler = async ({ locals, request, fetch }) => {
  try {
    const body = await request.json();
    const response = await fetch(`${API_URL}/api/scratchpad`, {
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
    console.error('Failed to save scratchpad:', error);
    return json({ error: 'Failed to save scratchpad' }, { status: 500 });
  }
};

export const DELETE: RequestHandler = async ({ locals, fetch }) => {
  try {
    const response = await fetch(`${API_URL}/api/scratchpad`, {
      method: 'DELETE',
      headers: buildAuthHeaders(locals)
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
