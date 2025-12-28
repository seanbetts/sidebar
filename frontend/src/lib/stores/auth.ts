import { writable } from 'svelte/store';
import type { Session, User } from '@supabase/supabase-js';
import { initSupabaseClient } from '$lib/supabase';
import { invalidateAll } from '$app/navigation';

export const session = writable<Session | null>(null);
export const user = writable<User | null>(null);

export function initAuth(
  initialSession: Session | null,
  initialUser: User | null,
  supabaseUrl: string,
  supabaseAnonKey: string
) {
  const supabase = initSupabaseClient(supabaseUrl, supabaseAnonKey);
  session.set(initialSession);
  user.set(initialUser);

  supabase.auth.onAuthStateChange((_event, newSession) => {
    session.set(newSession);
    user.set(newSession?.user ?? null);
    void invalidateAll();
  });
}
