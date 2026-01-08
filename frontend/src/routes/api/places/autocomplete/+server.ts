import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

import { createProxyHandler } from '$lib/server/apiProxy';

const proxyHandler = createProxyHandler({
	pathBuilder: () => '/api/v1/places/autocomplete',
	queryParamsFromUrl: true,
	responseType: 'text'
});

export const GET: RequestHandler = async (event) => {
	const input = event.url.searchParams.get('input');
	if (!input) {
		throw error(400, 'input is required');
	}

	return proxyHandler(event);
};
