import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getApiUrl, buildAuthHeaders } from '$lib/server/api';

const API_URL = getApiUrl();

export const POST: RequestHandler = async ({ locals, request, fetch }) => {
  try {
    const body = await request.json();
    const response = await fetch(`${API_URL}/api/v1/notes/folders`, {
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
    console.error('Failed to create folder:', error);
    return json({ error: 'Failed to create folder' }, { status: 500 });
  }
};

export const DELETE: RequestHandler = async ({ locals, request, fetch }) => {
  try {
    const body = await request.json();
    const response = await fetch(`${API_URL}/api/v1/notes/folders`, {
      method: 'DELETE',
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
    console.error('Failed to delete folder:', error);
    return json({ error: 'Failed to delete folder' }, { status: 500 });
  }
};
