import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

import { createProxyHandler } from '$lib/server/apiProxy';

const proxyHandler = createProxyHandler({
  pathBuilder: () => '/api/v1/places/reverse',
  queryParamsFromUrl: true,
  responseType: 'text'
});

export const GET: RequestHandler = async (event) => {
  const lat = event.url.searchParams.get('lat');
  const lng = event.url.searchParams.get('lng');
  if (!lat || !lng) {
    throw error(400, 'lat and lng are required');
  }

  return proxyHandler(event);
};
