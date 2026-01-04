import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

import { createProxyHandler } from '$lib/server/apiProxy';
import { logError } from '$lib/utils/errorHandling';

const proxyHandler = createProxyHandler({
  pathBuilder: () => '/api/v1/files/content',
  queryParamsFromUrl: true
});

export const GET: RequestHandler = async (event) => {
  const basePath = event.url.searchParams.get('basePath') || 'documents';
  if (basePath === 'notes') {
    return json({ error: 'Notes are served from /api/notes' }, { status: 400 });
  }

  return proxyHandler(event);
};

const postProxyHandler = createProxyHandler({
  method: 'POST',
  pathBuilder: () => '/api/v1/files/content',
  bodyFromRequest: true
});

export const POST: RequestHandler = async (event) => {
  let payload: { basePath?: string } | null = null;
  try {
    payload = JSON.parse(await event.request.clone().text());
  } catch (error) {
    logError('Failed to save file', error, { scope: 'api.files.content' });
    return json({ error: 'Failed to save file' }, { status: 500 });
  }

  if (payload?.basePath === 'notes') {
    return json({ error: 'Notes are served from /api/notes' }, { status: 400 });
  }

  return postProxyHandler(event);
};
