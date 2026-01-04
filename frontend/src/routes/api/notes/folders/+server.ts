import { createProxyHandler } from '$lib/server/apiProxy';

export const POST = createProxyHandler({
  method: 'POST',
  pathBuilder: () => '/api/v1/notes/folders',
  bodyFromRequest: true
});

export const DELETE = createProxyHandler({
  method: 'DELETE',
  pathBuilder: () => '/api/v1/notes/folders',
  bodyFromRequest: true
});
