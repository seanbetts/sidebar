import type { Handle } from '@sveltejs/kit';
import { createSupabaseServerClient } from '$lib/server/supabase';

export const handle: Handle = async ({ event, resolve }) => {
  event.locals.supabase = createSupabaseServerClient(event.cookies);

  const accessToken = getAccessTokenFromCookies(event);
  event.locals.session = accessToken ? { access_token: accessToken } : null;

  if (accessToken) {
    const {
      data: { user }
    } = await event.locals.supabase.auth.getUser();
    event.locals.user = user;
  } else {
    event.locals.user = null;
  }

  return resolve(event);
};

function getAccessTokenFromCookies(event: Parameters<Handle>[0]['event']): string | null {
  const storageKey = event.locals.supabase.auth.storageKey;
  const cookieName = storageKey ?? findSupabaseCookie(event);
  if (!cookieName) {
    return null;
  }

  const raw = event.cookies.get(cookieName);
  if (!raw) {
    return null;
  }

  const payload = parseCookiePayload(raw);
  if (Array.isArray(payload)) {
    const token = payload[0];
    return typeof token === 'string' ? token : null;
  }

  if (payload && typeof payload === 'object') {
    const token = (payload as { access_token?: unknown }).access_token;
    return typeof token === 'string' ? token : null;
  }

  return null;
}

function parseCookiePayload(raw: string): unknown {
  const value = raw.startsWith('base64-') ? decodeBase64(raw.slice(7)) : raw;
  if (!value) {
    return null;
  }

  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
}

function decodeBase64(value: string): string | null {
  try {
    return Buffer.from(value, 'base64').toString('utf-8');
  } catch {
    return null;
  }
}

function findSupabaseCookie(event: Parameters<Handle>[0]['event']): string | null {
  const match = event.cookies
    .getAll()
    .find((cookie) => cookie.name.startsWith('sb-') && cookie.name.endsWith('-auth-token'));
  return match?.name ?? null;
}
