import type { RequestHandler } from './$types';
import { getApiUrl, buildAuthHeaders } from '$lib/server/api';

const API_URL = getApiUrl();

export const GET: RequestHandler = async ({ locals, fetch, params }) => {
  const response = await fetch(`${API_URL}/api/v1/websites/${params.id}/download`, {
    headers: buildAuthHeaders(locals)
  });

  return new Response(response.body, {
    status: response.status,
    headers: response.headers
  });
};
