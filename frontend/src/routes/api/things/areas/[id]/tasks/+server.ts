import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getApiUrl, buildAuthHeaders } from '$lib/server/api';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ locals, params, fetch }) => {
  try {
    const response = await fetch(`${API_URL}/api/things/areas/${params.id}/tasks`, {
      headers: buildAuthHeaders(locals)
    });

    if (!response.ok) {
      throw new Error(`Backend API error: ${response.statusText}`);
    }

    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to load Things area tasks:', error);
    return json({ error: 'Failed to load Things area tasks' }, { status: 500 });
  }
};
