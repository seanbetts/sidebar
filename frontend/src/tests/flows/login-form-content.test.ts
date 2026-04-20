import { render, screen } from '@testing-library/svelte';
import { readable } from 'svelte/store';
import { describe, expect, it, vi } from 'vitest';
import LoginFormWithProviders from '../fixtures/LoginFormWithProviders.svelte';

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
		render(LoginFormWithProviders);
		expect(screen.getByText('Your session expired. Please sign in again.')).toBeInTheDocument();
	});

	it('uses the redesigned sign in wording and footer links', () => {
		render(LoginFormWithProviders);
		expect(screen.getByRole('link', { name: 'sideBar home' })).toBeInTheDocument();
		expect(screen.getByRole('link', { name: 'Home' })).toBeInTheDocument();
		expect(screen.getByRole('link', { name: 'About' })).toBeInTheDocument();
		expect(screen.getByRole('link', { name: 'Pricing' })).toBeInTheDocument();
		expect(screen.getByRole('link', { name: 'Docs' })).toBeInTheDocument();
		expect(
			screen.getByRole('button', { name: /switch to (light|dark) mode/i })
		).toBeInTheDocument();
		expect(screen.getByText('Welcome back')).toBeInTheDocument();
		expect(screen.getByRole('button', { name: 'Sign in' })).toBeInTheDocument();
		expect(screen.getByRole('link', { name: 'Privacy Policy' })).toBeInTheDocument();
		expect(screen.getByRole('link', { name: 'Terms of Service' })).toBeInTheDocument();
		expect(screen.getByRole('link', { name: 'EULA' })).toBeInTheDocument();
		expect(screen.queryByText(/Made with/i)).not.toBeInTheDocument();
	});
});
