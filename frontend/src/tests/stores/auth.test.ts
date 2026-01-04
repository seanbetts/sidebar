import { describe, expect, it, vi, beforeEach } from 'vitest';
import { get } from 'svelte/store';

let onAuthStateChangeHandler: ((event: string, session: any) => void) | null = null;

const { initSupabaseClient } = vi.hoisted(() => ({
  initSupabaseClient: vi.fn()
}));

const { invalidateAll } = vi.hoisted(() => ({
  invalidateAll: vi.fn()
}));

vi.mock('$lib/supabase', () => ({ initSupabaseClient }));
vi.mock('$app/navigation', () => ({ invalidateAll }));

describe('auth store', () => {
  beforeEach(() => {
    onAuthStateChangeHandler = null;
    initSupabaseClient.mockReset();
    invalidateAll.mockReset();
  });

  it('initializes session and user, then hydrates session', async () => {
    const realtime = { setAuth: vi.fn() };
    const auth = {
      getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: 'hydrated' } } }),
      onAuthStateChange: vi.fn((handler: (event: string, session: any) => void) => {
        onAuthStateChangeHandler = handler;
        return { data: { subscription: { unsubscribe: vi.fn() } } };
      }),
      getUser: vi.fn().mockResolvedValue({ data: { user: { id: 'user-1' } }, error: null })
    };
    initSupabaseClient.mockReturnValue({ realtime, auth });

    const { initAuth, session, user } = await import('$lib/stores/auth');

    initAuth({ access_token: 'initial' } as any, { id: 'user-0' } as any, 'url', 'key');

    expect(get(session)?.access_token).toBe('initial');
    expect(get(user)?.id).toBe('user-0');
    expect(realtime.setAuth).toHaveBeenCalledWith('initial');

    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(get(session)?.access_token).toBe('hydrated');
    expect(realtime.setAuth).toHaveBeenCalledWith('hydrated');
  });

  it('updates user on auth state change', async () => {
    const realtime = { setAuth: vi.fn() };
    const auth = {
      getSession: vi.fn().mockResolvedValue({ data: {} }),
      onAuthStateChange: vi.fn((handler: (event: string, session: any) => void) => {
        onAuthStateChangeHandler = handler;
        return { data: { subscription: { unsubscribe: vi.fn() } } };
      }),
      getUser: vi.fn().mockResolvedValue({ data: { user: { id: 'user-2' } }, error: null })
    };
    initSupabaseClient.mockReturnValue({ realtime, auth });

    const { initAuth, user } = await import('$lib/stores/auth');

    initAuth(null, null, 'url', 'key');
    expect(onAuthStateChangeHandler).not.toBeNull();

    await onAuthStateChangeHandler?.('SIGNED_IN', { access_token: 'token' });
    expect(realtime.setAuth).toHaveBeenCalledWith('token');
    expect(get(user)?.id).toBe('user-2');
    expect(invalidateAll).toHaveBeenCalled();
  });
});
