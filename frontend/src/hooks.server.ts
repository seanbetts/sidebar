import type { Handle } from '@sveltejs/kit';
import { createSupabaseServerClient } from '$lib/server/supabase';

export const handle: Handle = async ({ event, resolve }) => {
  event.locals.supabase = createSupabaseServerClient(event.cookies);

  const {
    data: { session }
  } = await event.locals.supabase.auth.getSession();
  event.locals.session = session;

  if (session) {
    const {
      data: { user }
    } = await event.locals.supabase.auth.getUser();
    event.locals.user = user;
  } else {
    event.locals.user = null;
  }

  return resolve(event);
};
