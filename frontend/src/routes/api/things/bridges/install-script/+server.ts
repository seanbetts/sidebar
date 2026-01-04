import type { RequestHandler } from './$types';

import { createProxyHandler } from '$lib/server/apiProxy';

export const POST: RequestHandler = createProxyHandler({
  method: 'POST',
  pathBuilder: () => '/api/v1/things/bridges/install-script',
  responseType: 'text'
});
