import { createProxyHandler } from '$lib/server/apiProxy';

export const GET = createProxyHandler({
  pathBuilder: (params) => `/api/v1/memories/${params.id}`
});

export const PATCH = createProxyHandler({
  method: 'PATCH',
  pathBuilder: (params) => `/api/v1/memories/${params.id}`,
  bodyFromRequest: true
});

export const DELETE = createProxyHandler({
  method: 'DELETE',
  pathBuilder: (params) => `/api/v1/memories/${params.id}`
});
