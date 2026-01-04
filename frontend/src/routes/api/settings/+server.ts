import type { RequestHandler } from './$types';

import { createProxyHandler } from '$lib/server/apiProxy';

const proxyHandler = createProxyHandler({
  pathBuilder: () => '/api/v1/settings',
  responseType: 'text'
});

export const GET: RequestHandler = proxyHandler;

export const PATCH: RequestHandler = createProxyHandler({
  method: 'PATCH',
  pathBuilder: () => '/api/v1/settings',
  bodyFromRequest: true,
  responseType: 'text'
});
