import { createProxyHandler } from '$lib/server/apiProxy';

export const POST = createProxyHandler({
	method: 'POST',
	pathBuilder: () => '/api/v1/tasks/apply',
	bodyFromRequest: true
});
