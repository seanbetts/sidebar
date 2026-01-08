import { createProxyHandler } from '$lib/server/apiProxy';

export const GET = createProxyHandler({
	pathBuilder: () => '/api/v1/scratchpad'
});

export const POST = createProxyHandler({
	method: 'POST',
	pathBuilder: () => '/api/v1/scratchpad',
	bodyFromRequest: true
});

export const DELETE = createProxyHandler({
	method: 'DELETE',
	pathBuilder: () => '/api/v1/scratchpad'
});
