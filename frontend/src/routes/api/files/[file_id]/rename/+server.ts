import { createProxyHandler } from '$lib/server/apiProxy';

export const PATCH = createProxyHandler({
	method: 'PATCH',
	pathBuilder: (params) => `/api/v1/files/${params.file_id}/rename`,
	bodyFromRequest: true
});
