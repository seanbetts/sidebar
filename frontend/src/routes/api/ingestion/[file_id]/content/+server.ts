import type { RequestHandler } from './$types';
import { buildAuthHeaders, getApiUrl } from '$lib/server/api';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ locals, params, url, fetch }) => {
  const kind = url.searchParams.get('kind');
  if (!kind) {
    return new Response('kind is required', { status: 400 });
  }
  try {
    const response = await fetch(`${API_URL}/api/ingestion/${params.file_id}/content?kind=${encodeURIComponent(kind)}`, {
      headers: buildAuthHeaders(locals)
    });
    if (!response.ok) {
      return new Response('Failed to fetch content', { status: response.status });
    }
    const body = await response.arrayBuffer();
    return new Response(body, {
      headers: {
        'Content-Type': response.headers.get('Content-Type') || 'application/octet-stream',
        'Content-Disposition': response.headers.get('Content-Disposition') || 'inline'
      }
    });
  } catch (error) {
    console.error('Failed to stream ingestion content:', error);
    return new Response('Failed to fetch content', { status: 500 });
  }
};
