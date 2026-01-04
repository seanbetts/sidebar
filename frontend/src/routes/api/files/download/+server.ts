import type { RequestHandler } from './$types';
import { getApiUrl, buildAuthHeaders } from '$lib/server/api';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ locals, fetch, url }) => {
  const basePath = url.searchParams.get('basePath') || 'documents';
  const path = url.searchParams.get('path') || '';

  const response = await fetch(
    `${API_URL}/api/v1/files/download?basePath=${encodeURIComponent(basePath)}&path=${encodeURIComponent(path)}`,
    {
      headers: buildAuthHeaders(locals)
    }
  );

  return new Response(response.body, {
    status: response.status,
    headers: response.headers
  });
};
