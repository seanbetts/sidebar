import { env } from '$env/dynamic/private';
import { error } from '@sveltejs/kit';
import type { App } from '@sveltejs/kit';

/**
 * Resolve backend API base URL for server requests.
 *
 * @returns Backend API base URL.
 */
export function getApiUrl(): string {
  return env.API_URL || 'http://skills-api:8001';
}

/**
 * Check whether auth dev mode is enabled.
 *
 * @returns True when auth dev mode is enabled.
 */
function isAuthDevMode(): boolean {
  const value = env.AUTH_DEV_MODE || '';
  return value.toLowerCase() === 'true' || value === '1';
}

/**
 * Extract the bearer token from the current session.
 *
 * @param locals SvelteKit request locals.
 * @returns Access token string.
 */
export function getSessionToken(locals: App.Locals): string {
  if (!locals.session) {
    throw error(401, 'Unauthorized');
  }
  return locals.session.access_token;
}

/**
 * Build Authorization headers for backend requests.
 *
 * @param locals SvelteKit request locals.
 * @param extra Additional header entries.
 * @returns Header map for backend requests.
 */
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
