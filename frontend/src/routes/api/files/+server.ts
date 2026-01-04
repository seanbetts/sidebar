import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

import { createProxyHandler } from '$lib/server/apiProxy';

const handler = createProxyHandler({
  pathBuilder: () => '/api/v1/files/tree',
  queryParamsFromUrl: true
});

export const GET: RequestHandler = async (event) => {
  const basePath = event.url.searchParams.get('basePath') || 'documents';
  if (basePath === 'notes') {
    return json({ error: 'Notes are served from /api/notes' }, { status: 400 });
  }

  if (!event.url.searchParams.has('basePath')) {
    const url = new URL(event.url);
    url.searchParams.set('basePath', basePath);
    return handler({ ...event, url });
  }

  return handler(event);
};
