import type { RequestHandler } from './$types';
import { buildAuthHeaders, getApiUrl } from '$lib/server/api';

const API_URL = getApiUrl();
const FORWARD_HEADERS = ['accept', 'content-type', 'if-modified-since', 'if-none-match', 'range'];

const handler: RequestHandler = async ({ request, params, url, locals, fetch }) => {
  const rawPath = url.pathname.replace(/^\/api\/v1/, '');
  const targetUrl = `${API_URL}/api/v1${rawPath}${url.search}`;

  const headers = new Headers();
  for (const header of FORWARD_HEADERS) {
    const value = request.headers.get(header);
    if (value) {
      headers.set(header, value);
    }
  }

  try {
    const authHeaders = buildAuthHeaders(locals);
    for (const [key, value] of Object.entries(authHeaders)) {
      headers.set(key, value);
    }
  } catch {
    // Allow unauthenticated requests; backend will reject if required.
  }

  const method = request.method;
  const body = method === 'GET' || method === 'HEAD' ? undefined : request.body;
  const init: RequestInit & { duplex?: 'half' } = {
    method,
    headers,
    body,
    redirect: 'manual'
  };

  if (body) {
    init.duplex = 'half';
  }

  const response = await fetch(targetUrl, init);
  return new Response(response.body, {
    status: response.status,
    headers: response.headers
  });
};

export const GET = handler;
export const POST = handler;
export const PUT = handler;
export const PATCH = handler;
export const DELETE = handler;
export const OPTIONS = handler;
export const HEAD = handler;
