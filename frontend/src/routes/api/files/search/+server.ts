import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

import { createProxyHandler } from '$lib/server/apiProxy';

const handler = createProxyHandler({
	method: 'POST',
	pathBuilder: () => '/api/v1/files/search',
	queryParamsFromUrl: true
});

export const POST: RequestHandler = async (event) => {
	const basePath = event.url.searchParams.get('basePath') || 'documents';
	if (basePath === 'notes') {
		return json({ error: 'Notes are served from /api/notes' }, { status: 400 });
	}

	const url = new URL(event.url);
	if (!url.searchParams.has('basePath')) {
		url.searchParams.set('basePath', basePath);
	}
	if (!url.searchParams.has('query')) {
		url.searchParams.set('query', '');
	}
	if (!url.searchParams.has('limit')) {
		url.searchParams.set('limit', '50');
	}

	return handler({ ...event, url });
};
