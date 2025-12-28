import { env } from '$env/dynamic/private';
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async ({ locals }) => {
  return {
    maintenanceMode: env.MAINTENANCE_MODE === 'true',
    session: locals.session ?? null,
    user: locals.user ?? null
  };
};
