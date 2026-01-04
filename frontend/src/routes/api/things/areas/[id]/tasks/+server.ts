import { createProxyHandler } from '$lib/server/apiProxy';

export const GET = createProxyHandler({
  pathBuilder: (params) => `/api/v1/things/areas/${params.id}/tasks`
});
