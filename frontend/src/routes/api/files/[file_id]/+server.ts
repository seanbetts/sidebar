import { createProxyHandler } from '$lib/server/apiProxy';

export const DELETE = createProxyHandler({
	method: 'DELETE',
	pathBuilder: (params) => `/api/v1/files/${params.file_id}`
});
