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

    await goto(redirectTo, { invalidateAll: true });
  }
</script>

<div class="login-shell">
  <div class="login-grid">
    <section class="login-hero">
      <h1 class="login-hero-title">
        <img src="/images/logo.svg" alt="sideBar" />
        <span>Welcome to sideBar</span>
      </h1>
      <p class="login-description">
        sideBar keeps your workspace focused. Capture ideas, save research, and keep important
        conversations in one place. Everything stays organised and searchable.
      </p>
      <div class="login-features">
        <span>Notes that stay structured</span>
        <span>Web captures you can revisit</span>
        <span>Files and conversations together</span>
      </div>
    </section>

    <section class="login-panel">
      <div class="login-panel-header">
        <img src="/images/logo.svg" alt="sideBar" />
        <div class="login-wordmark">sideBar</div>
      </div>

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
    </section>
  </div>
</div>

<style>
  .login-shell {
    min-height: 100vh;
    display: grid;
    place-items: center;
    padding: 3rem 1.5rem;
    position: relative;
    overflow: hidden;
    background: #000;
  }

  .login-grid {
    width: min(96vw, 1100px);
    display: grid;
    grid-template-columns: minmax(0, 1.2fr) minmax(0, 0.8fr);
    gap: 2.5rem;
    align-items: stretch;
  }

  .login-wordmark {
    font-size: 1.5rem;
    font-weight: 600;
    letter-spacing: 0.02em;
    color: var(--color-foreground);
  }

  .login-hero {
    padding: 2.5rem 2.75rem;
    border-radius: 1.75rem;
    border: 1px solid color-mix(in oklab, var(--color-border) 70%, transparent);
    background: color-mix(in oklab, var(--color-card) 88%, black 12%);
    box-shadow: 0 24px 48px rgba(0, 0, 0, 0.35);
    position: relative;
  }

  .login-hero-title {
    display: flex;
    align-items: center;
    gap: 0.85rem;
    margin: 0 0 0.75rem;
    font-size: 2rem;
    font-weight: 600;
  }

  .login-hero-title img {
    width: 44px;
    height: 44px;
  }

  .login-description {
    margin: 0 0 1.5rem;
    font-size: 1rem;
    color: var(--color-muted-foreground);
    line-height: 1.6;
  }

  .login-features {
    display: grid;
    gap: 0.75rem;
    font-size: 0.9rem;
    color: var(--color-foreground);
  }

  .login-features span {
    display: flex;
    align-items: center;
    gap: 0.6rem;
  }

  .login-features span::before {
    content: '';
    width: 8px;
    height: 8px;
    border-radius: 999px;
    background: var(--color-foreground);
  }

  .login-panel {
    padding: 2.5rem 2.25rem;
    border-radius: 1.5rem;
    border: 1px solid color-mix(in oklab, var(--color-border) 70%, transparent);
    background: color-mix(in oklab, var(--color-card) 92%, black 8%);
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
    box-shadow: 0 18px 36px rgba(0, 0, 0, 0.3);
  }

  .login-panel-header {
    display: flex;
    align-items: center;
    gap: 0.75rem;
  }

  .login-panel-header img {
    width: 34px;
    height: 34px;
  }

  .login-panel h1 {
    margin: 0;
    font-size: 1.25rem;
    font-weight: 600;
  }

  form {
    display: flex;
    flex-direction: column;
    gap: 1.15rem;
  }

  label {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    font-size: 0.85rem;
    color: var(--color-muted-foreground);
  }

  input {
    padding: 0.75rem 0.9rem;
    border: 1px solid color-mix(in oklab, var(--color-border) 70%, transparent);
    border-radius: 0.85rem;
    background: rgba(8, 8, 10, 0.65);
    color: var(--color-foreground);
    font-size: 0.95rem;
    transition: border-color 0.15s ease, box-shadow 0.15s ease;
  }

  input:focus {
    outline: none;
    border-color: color-mix(in oklab, var(--color-primary) 50%, transparent);
    box-shadow: 0 0 0 3px color-mix(in oklab, var(--color-primary) 30%, transparent);
  }

  .login-error {
    margin-bottom: 1rem;
    padding: 0.75rem 0.9rem;
    border-radius: 0.85rem;
    background: color-mix(in oklab, var(--color-destructive) 14%, transparent);
    color: var(--color-destructive);
    font-size: 0.9rem;
  }

  :global(.login-panel button) {
    margin-top: 0.4rem;
  }

  @media (max-width: 900px) {
    .login-grid {
      grid-template-columns: 1fr;
    }

    .login-hero,
    .login-panel {
      padding: 2.1rem 1.8rem;
    }
  }
</style>
