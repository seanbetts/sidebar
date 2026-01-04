import type { RequestHandler } from './$types';

import { createProxyHandler } from '$lib/server/apiProxy';

const proxyHandler = createProxyHandler({
  pathBuilder: (params) => `/api/v1/ingestion/${params.file_id}/content`,
  queryParamsFromUrl: true,
  responseType: 'stream'
});

export const GET: RequestHandler = async (event) => {
  const kind = event.url.searchParams.get('kind');
  if (!kind) {
    return new Response('kind is required', { status: 400 });
  }

  return proxyHandler(event);
};
