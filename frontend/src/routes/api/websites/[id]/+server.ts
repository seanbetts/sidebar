import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getApiUrl, buildAuthHeaders } from '$lib/server/api';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ locals, fetch, params }) => {
  try {
    const response = await fetch(`${API_URL}/api/v1/websites/${params.id}`, {
      headers: buildAuthHeaders(locals)
    });

    if (!response.ok) {
      throw new Error(`Backend API error: ${response.statusText}`);
    }

    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to fetch website:', error);
    return json({ error: 'Failed to load website' }, { status: 500 });
  }
};

export const DELETE: RequestHandler = async ({ locals, fetch, params }) => {
  try {
    const response = await fetch(`${API_URL}/api/v1/websites/${params.id}`, {
      method: 'DELETE',
      headers: buildAuthHeaders(locals)
    });

    if (!response.ok) {
      throw new Error(`Backend API error: ${response.statusText}`);
    }

    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to delete website:', error);
    return json({ error: 'Failed to delete website' }, { status: 500 });
  }
};
