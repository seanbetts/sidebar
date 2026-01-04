import { text } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getApiUrl, buildAuthHeaders } from '$lib/server/api';

const API_URL = getApiUrl();

export const POST: RequestHandler = async ({ locals, fetch }) => {
  try {
    const response = await fetch(`${API_URL}/api/v1/things/bridges/install-script`, {
      method: 'POST',
      headers: buildAuthHeaders(locals)
    });

    if (!response.ok) {
      throw new Error(`Backend API error: ${response.statusText}`);
    }

    const script = await response.text();
    return text(script);
  } catch (error) {
    console.error('Failed to create Things install script:', error);
    return text('Failed to create Things install script', { status: 500 });
  }
};
