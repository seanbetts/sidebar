import { redirect } from '@sveltejs/kit';
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async ({ locals, url }) => {
	if (!locals.session) {
		const redirectTo = encodeURIComponent(`${url.pathname}${url.search}`);
		throw redirect(303, `/auth/login?redirectTo=${redirectTo}`);
	}

	return {
		session: locals.session,
		user: locals.user
	};
};
