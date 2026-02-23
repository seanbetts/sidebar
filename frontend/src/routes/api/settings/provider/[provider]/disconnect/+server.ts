import { createProxyHandler } from '$lib/server/apiProxy';

export const POST = createProxyHandler({
	method: 'POST',
	pathBuilder: (params) => `/api/v1/settings/provider/${params.provider}/disconnect`,
	bodyFromRequest: true
});
