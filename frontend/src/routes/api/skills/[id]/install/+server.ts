import { createProxyHandler } from '$lib/server/apiProxy';

export const POST = createProxyHandler({
	method: 'POST',
	pathBuilder: (params) => `/api/v1/skills/${params.id}/install`,
	bodyFromRequest: true
});
