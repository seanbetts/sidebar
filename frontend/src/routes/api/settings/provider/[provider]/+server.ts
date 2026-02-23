import { createProxyHandler } from '$lib/server/apiProxy';

export const GET = createProxyHandler({
	pathBuilder: (params) => `/api/v1/settings/provider/${params.provider}`
});

export const POST = createProxyHandler({
	method: 'POST',
	pathBuilder: (params) => `/api/v1/settings/provider/${params.provider}`,
	bodyFromRequest: true
});

export const DELETE = createProxyHandler({
	method: 'DELETE',
	pathBuilder: (params) => `/api/v1/settings/provider/${params.provider}`
});
