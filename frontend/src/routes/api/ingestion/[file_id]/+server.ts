import { createProxyHandler } from '$lib/server/apiProxy';

export const DELETE = createProxyHandler({
	method: 'DELETE',
	pathBuilder: (params) => `/api/v1/ingestion/${params.file_id}`
});
