import { render, screen, waitFor } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { readable } from 'svelte/store';
import { describe, expect, it, vi } from 'vitest';
import LoginForm from '$lib/components/auth/LoginForm.svelte';

const { signInWithPassword, goto } = vi.hoisted(() => ({
	signInWithPassword: vi.fn(),
	goto: vi.fn()
}));

vi.mock('$app/navigation', () => ({
	goto
}));

vi.mock('$app/stores', () => ({
	page: readable({ url: new URL('http://localhost/login') })
}));

vi.mock('$lib/supabase', () => ({
	getSupabaseClient: () => ({
		auth: {
			signInWithPassword
		}
	})
}));

describe('authentication flow', () => {
	it('signs in and redirects on success', async () => {
		signInWithPassword.mockResolvedValue({ error: null });
		const user = userEvent.setup();

		render(LoginForm);

		await user.type(screen.getByLabelText('Email'), 'test@example.com');
		await user.type(screen.getByLabelText('Password'), 'password123');
		await user.click(screen.getByRole('button', { name: /sign in/i }));

		await waitFor(() => {
			expect(signInWithPassword).toHaveBeenCalledWith({
				email: 'test@example.com',
				password: 'password123'
			});
		});

		expect(goto).toHaveBeenCalledWith('/', { invalidateAll: true });
	});
});
