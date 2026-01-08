import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

import { createProxyHandler } from '$lib/server/apiProxy';

const handler = createProxyHandler({
	pathBuilder: () => '/api/v1/things/search',
	queryParamsFromUrl: true
});

export const GET: RequestHandler = async (event) => {
	const query = (event.url.searchParams.get('query') || '').trim();
	if (!query) {
		return json({ error: 'query required' }, { status: 400 });
	}

	return handler(event);
};
