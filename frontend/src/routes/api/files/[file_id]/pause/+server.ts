import { createProxyHandler } from '$lib/server/apiProxy';

export const POST = createProxyHandler({
	method: 'POST',
	pathBuilder: (params) => `/api/v1/files/${params.file_id}/pause`
});
