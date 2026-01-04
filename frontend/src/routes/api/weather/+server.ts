import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

import { createProxyHandler } from '$lib/server/apiProxy';

const proxyHandler = createProxyHandler({
  pathBuilder: () => '/api/v1/weather',
  queryParamsFromUrl: true,
  responseType: 'text'
});

export const GET: RequestHandler = async (event) => {
  const lat = event.url.searchParams.get('lat');
  const lon = event.url.searchParams.get('lon');
  if (!lat || !lon) {
    throw error(400, 'lat and lon are required');
  }

  const response = await proxyHandler(event);
  const text = await response.text();
  const headers = new Headers(response.headers);
  headers.set('Cache-Control', 'max-age=1800');

  return new Response(text, {
    status: response.status,
    headers
  });
};
