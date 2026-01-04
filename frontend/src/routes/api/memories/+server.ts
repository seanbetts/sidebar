import { createProxyHandler } from '$lib/server/apiProxy';

export const GET = createProxyHandler({
  pathBuilder: () => '/api/v1/memories'
});

export const POST = createProxyHandler({
  method: 'POST',
  pathBuilder: () => '/api/v1/memories',
  bodyFromRequest: true
});
