import { writable } from 'svelte/store';
import type { Session, User } from '@supabase/supabase-js';
import { initSupabaseClient } from '$lib/supabase';
import { invalidateAll } from '$app/navigation';

export const session = writable<Session | null>(null);
export const user = writable<User | null>(null);

/**
 * Initialize auth state and keep session/user in sync.
 *
 * @param initialSession Initial session payload.
 * @param initialUser Initial user payload.
 * @param supabaseUrl Supabase project URL.
 * @param supabaseAnonKey Supabase anon key.
 */
export function initAuth(
	initialSession: Session | null,
	initialUser: User | null,
	supabaseUrl: string,
	supabaseAnonKey: string
) {
	const supabase = initSupabaseClient(supabaseUrl, supabaseAnonKey);
	session.set(initialSession);
	user.set(initialUser);
	if (initialSession?.access_token) {
		supabase.realtime.setAuth(initialSession.access_token);
	}

	// Ensure we hydrate the session on first load (onAuthStateChange may not fire).
	supabase.auth
		.getSession()
		.then(({ data }) => {
			if (data?.session) {
				session.set(data.session);
				supabase.realtime.setAuth(data.session.access_token);
			}
		})
		.catch((error) => {
			console.warn('Failed to load initial session:', error);
		});

	supabase.auth.onAuthStateChange(async (_event, newSession) => {
		session.set(newSession);
		if (newSession?.access_token) {
			supabase.realtime.setAuth(newSession.access_token);
		}
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
