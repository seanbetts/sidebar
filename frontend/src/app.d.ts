import type { SupabaseClient, User } from '@supabase/supabase-js';

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
