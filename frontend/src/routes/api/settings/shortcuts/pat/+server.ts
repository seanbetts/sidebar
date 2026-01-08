import type { RequestHandler } from './$types';

import { createProxyHandler } from '$lib/server/apiProxy';

export const GET: RequestHandler = createProxyHandler({
	pathBuilder: () => '/api/v1/settings/shortcuts/pat',
	responseType: 'text'
});
