import { env } from '$env/dynamic/private';
import { error } from '@sveltejs/kit';
import type { App } from '@sveltejs/kit';

export function getApiUrl(): string {
  return env.API_URL || 'http://skills-api:8001';
}

export function getSessionToken(locals: App.Locals): string {
  if (!locals.session) {
    throw error(401, 'Unauthorized');
  }
  return locals.session.access_token;
}

export function buildAuthHeaders(
  locals: App.Locals,
  extra: Record<string, string> = {}
): Record<string, string> {
  return {
    Authorization: `Bearer ${getSessionToken(locals)}`,
    ...extra
  };
}
