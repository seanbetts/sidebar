import { env } from '$env/dynamic/private';
import { error } from '@sveltejs/kit';
import type { App } from '@sveltejs/kit';

export function getApiUrl(): string {
  return env.API_URL || 'http://skills-api:8001';
}

function isAuthDevMode(): boolean {
  const value = env.AUTH_DEV_MODE || '';
  return value.toLowerCase() === 'true' || value === '1';
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
  if (!locals.session) {
    if (isAuthDevMode()) {
      return { ...extra };
    }
    throw error(401, 'Unauthorized');
  }
  return {
    Authorization: `Bearer ${locals.session.access_token}`,
    ...extra
  };
}
