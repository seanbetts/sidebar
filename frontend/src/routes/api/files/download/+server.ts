import type { RequestHandler } from './$types';

const API_URL = process.env.API_URL || 'http://skills-api:8001';
const BEARER_TOKEN = process.env.BEARER_TOKEN || '';

export const GET: RequestHandler = async ({ fetch, url }) => {
  const basePath = url.searchParams.get('basePath') || 'documents';
  const path = url.searchParams.get('path') || '';

  const response = await fetch(
    `${API_URL}/api/files/download?basePath=${encodeURIComponent(basePath)}&path=${encodeURIComponent(path)}`,
    {
      headers: {
        'Authorization': `Bearer ${BEARER_TOKEN}`
      }
    }
  );

  return new Response(response.body, {
    status: response.status,
    headers: response.headers
  });
};
