<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/stores';
  import { getSupabaseClient } from '$lib/supabase';
  import { Button } from '$lib/components/ui/button';

  let email = '';
  let password = '';
  let loading = false;
  let error = '';
  $: redirectTo = $page.url.searchParams.get('redirectTo') ?? '/';

  async function handleLogin(event: SubmitEvent) {
    event.preventDefault();
    loading = true;
    error = '';

    const supabase = getSupabaseClient();
    const { error: authError } = await supabase.auth.signInWithPassword({
      email,
      password
    });

    if (authError) {
      error = authError.message;
      loading = false;
      return;
    }

    await goto(redirectTo);
  }
</script>

<div class="login-container">
  <h1>Sign in to sideBar</h1>

  {#if error}
    <div class="login-error">{error}</div>
  {/if}

  <form on:submit={handleLogin}>
    <label>
      <span>Email</span>
      <input type="email" bind:value={email} autocomplete="email" required />
    </label>
    <label>
      <span>Password</span>
      <input type="password" bind:value={password} autocomplete="current-password" required />
    </label>
    <Button type="submit" disabled={loading}>
      {loading ? 'Signing in…' : 'Sign in'}
    </Button>
  </form>
</div>

<style>
  .login-container {
    width: min(92vw, 420px);
    margin: 6rem auto 0;
    padding: 2.5rem 2rem;
    border: 1px solid var(--color-border);
    border-radius: 1.25rem;
    background: var(--color-card);
    box-shadow: 0 12px 24px rgba(15, 23, 42, 0.08);
  }

  h1 {
    margin-bottom: 1.5rem;
    font-size: 1.35rem;
    font-weight: 600;
  }

  form {
    display: flex;
    flex-direction: column;
    gap: 1.25rem;
  }

  label {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    font-size: 0.9rem;
    color: var(--color-muted-foreground);
  }

  input {
    padding: 0.7rem 0.85rem;
    border: 1px solid var(--color-border);
    border-radius: 0.75rem;
    background: var(--color-background);
    color: var(--color-foreground);
    font-size: 0.95rem;
  }

  input:focus {
    outline: 2px solid color-mix(in oklab, var(--color-primary) 45%, transparent);
    outline-offset: 2px;
  }

  .login-error {
    margin-bottom: 1rem;
    padding: 0.75rem 0.9rem;
    border-radius: 0.75rem;
    background: color-mix(in oklab, var(--color-destructive) 12%, transparent);
    color: var(--color-destructive);
    font-size: 0.9rem;
  }
</style>
