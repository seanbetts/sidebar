import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

import { createProxyHandler } from '$lib/server/apiProxy';

const handler = createProxyHandler({
  method: 'POST',
  pathBuilder: () => '/api/v1/files/rename',
  bodyFromRequest: true
});

export const POST: RequestHandler = async (event) => {
  const body = await event.request.clone().json().catch(() => ({}));
  if (body?.basePath === 'notes') {
    return json({ error: 'Notes are served from /api/notes' }, { status: 400 });
  }

  return handler(event);
};
