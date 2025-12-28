import { createServerClient } from '@supabase/ssr';
import { env } from '$env/dynamic/private';
import type { Cookies } from '@sveltejs/kit';

export function createSupabaseServerClient(cookies: Cookies) {
  return createServerClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    cookies: {
      get: (key: string) => cookies.get(key),
      set: (key: string, value: string, options: CookieOptions) => {
        cookies.set(key, value, { ...options, path: '/' });
      },
      remove: (key: string, options: CookieOptions) => {
        cookies.delete(key, { ...options, path: '/' });
      }
    }
  });
}

interface CookieOptions {
  path?: string;
  expires?: Date;
  maxAge?: number;
  domain?: string;
  secure?: boolean;
  httpOnly?: boolean;
  sameSite?: 'lax' | 'strict' | 'none';
}
