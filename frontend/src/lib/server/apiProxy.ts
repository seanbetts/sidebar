import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';

import { buildAuthHeaders, getApiUrl } from '$lib/server/api';

/** Options for configuring a backend proxy handler. */
export type ProxyResponseType = 'json' | 'text' | 'stream';

export interface ProxyOptions {
  method?: string;
  pathBuilder: (params: Record<string, string>) => string;
  bodyFromRequest?: boolean;
  queryParamsFromUrl?: boolean;
  responseType?: ProxyResponseType;
}

/**
 * Create a SvelteKit request handler that proxies requests to the backend API.
 */
export function createProxyHandler(options: ProxyOptions): RequestHandler {
  const {
    method = 'GET',
    pathBuilder,
    bodyFromRequest = false,
    queryParamsFromUrl = false,
    responseType = 'json'
  } = options;

  return async ({ locals, fetch, params, request, url }) => {
    try {
      const path = pathBuilder(params);
      let backendUrl = `${getApiUrl()}${path}`;

      if (queryParamsFromUrl && url.search) {
        backendUrl += url.search;
      }

      const headers = buildAuthHeaders(locals);
      const requestOptions: RequestInit = {
        method,
        headers
      };

      if (bodyFromRequest && method !== 'GET' && method !== 'HEAD') {
        const contentType = request.headers.get('Content-Type');
        requestOptions.body = await request.text();
        requestOptions.headers = {
          ...headers,
          ...(contentType ? { 'Content-Type': contentType } : {})
        };
      }

      const response = await fetch(backendUrl, requestOptions);

      if (responseType === 'stream') {
        return new Response(response.body, {
          status: response.status,
          headers: response.headers
        });
      }

      if (responseType === 'text') {
        const text = await response.text();
        return new Response(text, {
          status: response.status,
          headers: response.headers
        });
      }

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({
          error: response.statusText
        }));
        return json(errorData, { status: response.status });
      }

      const data = await response.json();
      return json(data, { status: response.status });
    } catch (err) {
      console.error('API proxy error:', {
        path: pathBuilder(params),
        method,
        error: err
      });

      const message = err instanceof Error ? err.message : 'Internal server error';
      if (responseType !== 'json') {
        return new Response(message, { status: 500 });
      }
      return json({ error: message }, { status: 500 });
    }
  };
}
