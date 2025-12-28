import { createBrowserClient } from '@supabase/ssr';
import type { SupabaseClient } from '@supabase/supabase-js';

let supabaseClient: SupabaseClient | null = null;

export function initSupabaseClient(url: string, anonKey: string): SupabaseClient {
  if (!supabaseClient) {
    supabaseClient = createBrowserClient(url, anonKey);
  }
  return supabaseClient;
}

export function getSupabaseClient(): SupabaseClient {
  if (!supabaseClient) {
    throw new Error('Supabase client not initialized');
  }
  return supabaseClient;
}
