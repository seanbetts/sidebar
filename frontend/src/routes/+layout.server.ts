import { env } from '$env/dynamic/private';
import type { LayoutServerLoad } from './$types';

const HOLDING_PAGE_HOSTS = new Set([
	'trysidebar.ai',
	'www.trysidebar.ai',
	'trysidebar.localhost',
	'www.trysidebar.localhost'
]);

export const load: LayoutServerLoad = async ({ locals, url }) => {
	if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) {
		throw new Error('Missing SUPABASE_URL or SUPABASE_ANON_KEY');
	}
	const requestHost = url.hostname.toLowerCase();
	const isHoldingPageHost = HOLDING_PAGE_HOSTS.has(requestHost);

	return {
		maintenanceMode: env.MAINTENANCE_MODE === 'true' || isHoldingPageHost,
		supabaseUrl: env.SUPABASE_URL,
		supabaseAnonKey: env.SUPABASE_ANON_KEY,
		isAuthenticated: Boolean(locals.session),
		user: locals.user ?? null
	};
};
