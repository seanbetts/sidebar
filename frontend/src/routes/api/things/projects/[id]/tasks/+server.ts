import { createProxyHandler } from '$lib/server/apiProxy';

export const GET = createProxyHandler({
  pathBuilder: (params) => `/api/v1/things/projects/${params.id}/tasks`
});
