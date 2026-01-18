import { createProxyHandler } from '$lib/server/apiProxy';

export const PATCH = createProxyHandler({
	method: 'PATCH',
	pathBuilder: () => '/api/v1/files/pinned-order',
	bodyFromRequest: true
});
