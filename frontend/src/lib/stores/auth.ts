import { writable } from 'svelte/store';
import type { Session, User } from '@supabase/supabase-js';
import { supabase } from '$lib/supabase';

export const session = writable<Session | null>(null);
export const user = writable<User | null>(null);

export function initAuth(initialSession: Session | null, initialUser: User | null) {
  session.set(initialSession);
  user.set(initialUser);

  supabase.auth.onAuthStateChange((_event, newSession) => {
    session.set(newSession);
    user.set(newSession?.user ?? null);
  });
}
