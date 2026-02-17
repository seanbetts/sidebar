import { render, screen } from '@testing-library/svelte';
import { readable } from 'svelte/store';
import { describe, expect, it, vi } from 'vitest';
import LoginForm from '$lib/components/auth/LoginForm.svelte';

vi.mock('$app/navigation', () => ({
	goto: vi.fn()
}));

vi.mock('$app/stores', () => ({
	page: readable({ url: new URL('http://localhost/auth/login?reason=session_expired') })
}));

vi.mock('$lib/supabase', () => ({
	getSupabaseClient: () => ({
		auth: {
			signInWithPassword: vi.fn()
		}
	})
}));

describe('login form content', () => {
	it('shows the session-expired message', () => {
		render(LoginForm);
		expect(screen.getByText('Your session expired. Please sign in again.')).toBeInTheDocument();
	});

	it('uses sign in wording and shows tasks as a core feature', () => {
		render(LoginForm);
		expect(screen.getByText('Sign in', { selector: '.login-wordmark' })).toBeInTheDocument();
		expect(screen.getByRole('button', { name: 'Sign in' })).toBeInTheDocument();
		expect(screen.getByText('Task Management')).toBeInTheDocument();
	});
});
