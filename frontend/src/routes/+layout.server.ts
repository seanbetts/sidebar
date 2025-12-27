import { env } from '$env/dynamic/private';

export const load = () => {
  return {
    maintenanceMode: env.MAINTENANCE_MODE === 'true'
  };
};
