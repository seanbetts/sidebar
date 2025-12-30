import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { buildAuthHeaders, getApiUrl } from '$lib/server/api';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ locals, fetch }) => {
  try {
    const response = await fetch(`${API_URL}/api/ingestion`, {
      headers: buildAuthHeaders(locals)
    });
    if (!response.ok) {
      throw new Error(`Backend API error: ${response.statusText}`);
    }
    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to list ingestions:', error);
    return json({ error: 'Failed to list ingestions' }, { status: 500 });
  }
};

export const POST: RequestHandler = async ({ locals, request, fetch }) => {
  try {
    const formData = await request.formData();
    const response = await fetch(`${API_URL}/api/ingestion`, {
      method: 'POST',
      headers: buildAuthHeaders(locals),
      body: formData
    });
    if (!response.ok) {
      const detail = await response.text();
      throw new Error(detail || response.statusText);
    }
    const data = await response.json();
    return json(data);
  } catch (error) {
    console.error('Failed to upload ingestion file:', error);
    return json({ error: 'Failed to upload file' }, { status: 500 });
  }
};
