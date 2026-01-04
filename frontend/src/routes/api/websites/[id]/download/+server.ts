import { createProxyHandler } from '$lib/server/apiProxy';

export const GET = createProxyHandler({
  pathBuilder: (params) => `/api/v1/websites/${params.id}/download`,
  responseType: 'stream'
});
