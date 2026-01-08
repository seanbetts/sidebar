import { createProxyHandler } from '$lib/server/apiProxy';

export const GET = createProxyHandler({
	pathBuilder: (params) => `/api/v1/conversations/${params.id}`
});

export const PUT = createProxyHandler({
	method: 'PUT',
	pathBuilder: (params) => `/api/v1/conversations/${params.id}`,
	bodyFromRequest: true
});

export const DELETE = createProxyHandler({
	method: 'DELETE',
	pathBuilder: (params) => `/api/v1/conversations/${params.id}`
});
