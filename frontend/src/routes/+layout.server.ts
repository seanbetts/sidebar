import { env } from '$env/dynamic/private';
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async ({ locals }) => {
  return {
    maintenanceMode: env.MAINTENANCE_MODE === 'true',
    supabaseUrl: env.SUPABASE_URL,
    supabaseAnonKey: env.SUPABASE_ANON_KEY,
    isAuthenticated: Boolean(locals.session),
    user: locals.user ?? null
  };
};
