import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { buildAuthHeaders, getApiUrl } from '$lib/server/api';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ locals, fetch }) => {
  try {
    const response = await fetch(`${API_URL}/api/things/diagnostics`, {
      headers: buildAuthHeaders(locals)
    });
    if (!response.ok) {
      throw new Error(`Backend API error: ${response.statusText}`);
    }
    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to load Things diagnostics:', error);
    return json({ error: 'Failed to load Things diagnostics' }, { status: 500 });
  }
};
