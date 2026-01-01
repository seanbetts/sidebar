import { getApiUrl, buildAuthHeaders } from '$lib/server/api';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

const API_URL = getApiUrl();

export const POST: RequestHandler = async ({ locals }) => {
  try {
    const response = await fetch(`${API_URL}/api/settings/shortcuts/pat/rotate`, {
      method: 'POST',
      headers: buildAuthHeaders(locals)
    });

    if (!response.ok) {
      throw error(response.status, `Backend error: ${response.statusText}`);
    }

    return new Response(await response.text(), {
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (err) {
    console.error('Shortcuts PAT rotate error:', err);
    if (err instanceof Error && 'status' in err) {
      throw err;
    }
    throw error(500, 'Internal server error');
  }
};
