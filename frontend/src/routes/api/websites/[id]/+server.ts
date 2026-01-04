import { createProxyHandler } from '$lib/server/apiProxy';

export const GET = createProxyHandler({
  pathBuilder: (params) => `/api/v1/websites/${params.id}`
});

export const DELETE = createProxyHandler({
  method: 'DELETE',
  pathBuilder: (params) => `/api/v1/websites/${params.id}`
});
