import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getApiUrl, buildAuthHeaders } from '$lib/server/api';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ locals, fetch, params }) => {
  try {
    const response = await fetch(`${API_URL}/api/v1/memories/${params.id}`, {
      headers: buildAuthHeaders(locals)
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

export const PATCH: RequestHandler = async ({ locals, request, fetch, params }) => {
  try {
    const body = await request.json();
    const response = await fetch(`${API_URL}/api/v1/memories/${params.id}`, {
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
    console.error('Failed to update memory:', error);
    return json({ error: 'Failed to update memory' }, { status: 500 });
  }
};

export const DELETE: RequestHandler = async ({ locals, fetch, params }) => {
  try {
    const response = await fetch(`${API_URL}/api/v1/memories/${params.id}`, {
      method: 'DELETE',
      headers: buildAuthHeaders(locals)
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
