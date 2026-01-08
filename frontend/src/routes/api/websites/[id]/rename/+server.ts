import { createProxyHandler } from '$lib/server/apiProxy';

export const PATCH = createProxyHandler({
	method: 'PATCH',
	pathBuilder: (params) => `/api/v1/websites/${params.id}/rename`,
	bodyFromRequest: true
});
