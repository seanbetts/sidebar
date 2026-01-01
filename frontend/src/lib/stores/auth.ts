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

  supabase.auth.onAuthStateChange(async (_event, newSession) => {
    session.set(newSession);
    try {
      const { data, error } = await supabase.auth.getUser();
      if (error) {
        user.set(null);
      } else {
        user.set(data.user ?? null);
      }
    } catch {
      user.set(null);
    }
    void invalidateAll();
  });
}
