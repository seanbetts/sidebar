import { createProxyHandler } from '$lib/server/apiProxy';

export const GET = createProxyHandler({
	pathBuilder: () => '/api/v1/files/download',
	queryParamsFromUrl: true,
	responseType: 'stream'
});
