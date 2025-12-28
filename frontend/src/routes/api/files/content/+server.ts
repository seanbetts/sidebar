import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getApiUrl, buildAuthHeaders } from '$lib/server/api';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ locals, fetch, url }) => {
  try {
    const basePath = url.searchParams.get('basePath') || 'documents';
    const path = url.searchParams.get('path') || '';
    if (basePath === 'notes') {
      return json({ error: 'Notes are served from /api/notes' }, { status: 400 });
    }

    const response = await fetch(
      `${API_URL}/api/files/content?basePath=${encodeURIComponent(basePath)}&path=${encodeURIComponent(path)}`,
      {
        headers: buildAuthHeaders(locals)
      }
    );

    if (!response.ok) {
      throw new Error(`Backend API error: ${response.statusText}`);
    }

    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to load file:', error);
    return json({ error: 'Failed to load file' }, { status: 500 });
  }
};

export const POST: RequestHandler = async ({ locals, request, fetch }) => {
  try {
    const body = await request.json();
    if (body?.basePath === 'notes') {
      return json({ error: 'Notes are served from /api/notes' }, { status: 400 });
    }

    const response = await fetch(`${API_URL}/api/files/content`, {
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
    console.error('Failed to save file:', error);
    return json({ error: 'Failed to save file' }, { status: 500 });
  }
};
