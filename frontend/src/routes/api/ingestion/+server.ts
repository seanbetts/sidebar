import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

import { createProxyHandler } from '$lib/server/apiProxy';
import { buildAuthHeaders, getApiUrl } from '$lib/server/api';
import { logError } from '$lib/utils/errorHandling';

const API_URL = getApiUrl();

export const GET = createProxyHandler({
  pathBuilder: () => '/api/v1/ingestion'
});

export const POST: RequestHandler = async ({ locals, request, fetch }) => {
  try {
    const formData = await request.formData();
    const response = await fetch(`${API_URL}/api/v1/ingestion`, {
      method: 'POST',
      headers: buildAuthHeaders(locals),
      body: formData
    });
    if (!response.ok) {
      const detail = await response.text();
      return json(
        { detail: detail || response.statusText || 'Failed to upload file' },
        { status: response.status }
      );
    }
    const data = await response.json();
    return json(data);
  } catch (error) {
    logError('Failed to upload ingestion file', error, { scope: 'api.ingestion.upload' });
    return json({ error: 'Failed to upload file' }, { status: 500 });
  }
};
