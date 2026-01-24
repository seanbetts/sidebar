import { createProxyHandler } from '$lib/server/apiProxy';

export const GET = createProxyHandler({
	pathBuilder: (params) => `/api/v1/tasks/groups/${params.id}/tasks`
});
