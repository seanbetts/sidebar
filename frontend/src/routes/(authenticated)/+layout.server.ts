import { redirect } from '@sveltejs/kit';
import { env } from '$env/dynamic/private';
import type { LayoutServerLoad } from './$types';

const HOLDING_PAGE_HOSTS = new Set([
	'trysidebar.ai',
	'www.trysidebar.ai',
	'trysidebar.localhost',
	'www.trysidebar.localhost'
]);

export const load: LayoutServerLoad = async ({ locals, url }) => {
	const requestHost = url.hostname.toLowerCase();
	const isHoldingPageHost = HOLDING_PAGE_HOSTS.has(requestHost);
	const isHoldingPageEnabled = env.MAINTENANCE_MODE === 'true' || isHoldingPageHost;

	if (isHoldingPageEnabled) {
		return {
			session: locals.session,
			user: locals.user
		};
	}

	if (!locals.session) {
		const redirectTo = encodeURIComponent(`${url.pathname}${url.search}`);
		throw redirect(303, `/auth/login?redirectTo=${redirectTo}`);
	}

	return {
		session: locals.session,
		user: locals.user
	};
};
