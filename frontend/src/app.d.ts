import type { SupabaseClient, User } from '@supabase/supabase-js';

declare module '$env/static/public' {
  export const PUBLIC_ENABLE_WEB_VITALS: string | undefined;
  export const PUBLIC_METRICS_ENDPOINT: string | undefined;
  export const PUBLIC_WEB_VITALS_SAMPLE_RATE: string | undefined;
  export const PUBLIC_CHAT_METRICS_ENDPOINT: string | undefined;
  export const PUBLIC_CHAT_METRICS_SAMPLE_RATE: string | undefined;
  export const PUBLIC_SENTRY_DSN_FRONTEND: string | undefined;
  export const PUBLIC_SENTRY_ENVIRONMENT: string | undefined;
  export const PUBLIC_SENTRY_SAMPLE_RATE: string | undefined;
}

declare global {
  namespace App {
    interface Locals {
      supabase: SupabaseClient;
      session: { access_token: string } | null;
      user: User | null;
    }
  }
}

export {};
