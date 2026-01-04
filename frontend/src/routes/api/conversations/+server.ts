import { createProxyHandler } from '$lib/server/apiProxy';

export const GET = createProxyHandler({
  pathBuilder: () => '/api/v1/conversations/'
});

export const POST = createProxyHandler({
  method: 'POST',
  pathBuilder: () => '/api/v1/conversations/',
  bodyFromRequest: true
});
