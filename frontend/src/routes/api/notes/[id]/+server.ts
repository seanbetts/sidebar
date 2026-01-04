import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getApiUrl, buildAuthHeaders } from '$lib/server/api';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ locals, fetch, params }) => {
  try {
    const response = await fetch(`${API_URL}/api/v1/notes/${params.id}`, {
      headers: buildAuthHeaders(locals)
    });

    if (!response.ok) {
      throw new Error(`Backend API error: ${response.statusText}`);
    }

    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to load note:', error);
    return json({ error: 'Failed to load note' }, { status: 500 });
  }
};

export const PATCH: RequestHandler = async ({ locals, request, fetch, params }) => {
  try {
    const body = await request.json();
    const response = await fetch(`${API_URL}/api/v1/notes/${params.id}`, {
      method: 'PATCH',
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
    console.error('Failed to update note:', error);
    return json({ error: 'Failed to update note' }, { status: 500 });
  }
};

export const DELETE: RequestHandler = async ({ locals, fetch, params }) => {
  try {
    const response = await fetch(`${API_URL}/api/v1/notes/${params.id}`, {
      method: 'DELETE',
      headers: buildAuthHeaders(locals)
    });

    if (!response.ok) {
      throw new Error(`Backend API error: ${response.statusText}`);
    }

    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to delete note:', error);
    return json({ error: 'Failed to delete note' }, { status: 500 });
  }
};
