import { redirect } from '@sveltejs/kit';
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async ({ locals, url }) => {
  if (!locals.session) {
    throw redirect(303, `/auth/login?redirectTo=${url.pathname}`);
  }

  return {
    session: locals.session,
    user: locals.user
  };
};
