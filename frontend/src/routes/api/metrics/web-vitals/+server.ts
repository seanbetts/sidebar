import { json } from '@sveltejs/kit';
import { buildAuthHeaders, getApiUrl } from '$lib/server/api';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async ({ request, locals, fetch }) => {
  const payload = await request.text();
  if (!payload) {
    return json({ error: 'Missing payload' }, { status: 400 });
  }

  const response = await fetch(`${getApiUrl()}/api/v1/metrics/web-vitals`, {
    method: 'POST',
    headers: buildAuthHeaders(locals, {
      'Content-Type': 'application/json'
    }),
    body: payload
  });

  if (!response.ok) {
    return json({ error: 'Failed to record metric' }, { status: response.status });
  }

  return new Response(null, { status: 204 });
};
