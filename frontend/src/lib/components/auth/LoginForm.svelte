<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/stores';
  import { getSupabaseClient } from '$lib/supabase';
  import { Button } from '$lib/components/ui/button';
  import { MessageSquare, FileText, Globe, Brain, FolderOpen, Cloud } from 'lucide-svelte';

  let email = '';
  let password = '';
  let loading = false;
  let error = '';
  $: loggedOut = $page.url.searchParams.get('loggedOut') === '1';
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
  <div class="login-container">
    <div class="login-brand">
      <img src="/images/logo.svg" alt="sideBar" class="brand-logo" />
      <span class="brand-wordmark">sideBar</span>
    </div>

    <div class="login-grid">
      <section class="login-hero">
      <h1 class="login-hero-title">
        <img src="/images/logo.svg" alt="sideBar" class="hero-logo" />
        <span>Welcome to sideBar</span>
      </h1>
      <p class="login-tagline">Your AI-Powered Workspace</p>
      <p class="login-description">
        sideBar is an AI assistant, powered by Anthropic's Claude, that can access to your notes,
        saved websites, and files, giving every interaction AI superpowers!
      </p>

      <!-- Screenshot placeholder - you can add this later -->
      <!-- <div class="screenshot-placeholder">
        <img src="/images/screenshot.png" alt="sideBar workspace" />
      </div> -->

      <div class="login-features">
        <div class="feature">
          <MessageSquare size={18} strokeWidth={2} />
          <div class="feature-content">
            <span class="feature-title">Chat with Full Context</span>
            <span class="feature-desc">Work with sideBar while it accesses your notes, files, and research</span>
          </div>
        </div>
        <div class="feature">
          <FileText size={18} strokeWidth={2} />
          <div class="feature-content">
            <span class="feature-title">Smart Note-Taking</span>
            <span class="feature-desc">Markdown editor with AI-powered organisation and search</span>
          </div>
        </div>
        <div class="feature">
          <Globe size={18} strokeWidth={2} />
          <div class="feature-content">
            <span class="feature-title">Website Captures</span>
            <span class="feature-desc">Save full page content, not just bookmarks</span>
          </div>
        </div>
        <div class="feature">
          <Brain size={18} strokeWidth={2} />
          <div class="feature-content">
            <span class="feature-title">Memory System</span>
            <span class="feature-desc">sideBar remembers important context across conversations</span>
          </div>
        </div>
        <div class="feature">
          <FolderOpen size={18} strokeWidth={2} />
          <div class="feature-content">
            <span class="feature-title">File Intelligence</span>
            <span class="feature-desc">Upload documents and discuss them with sideBar</span>
          </div>
        </div>
        <div class="feature">
          <Cloud size={18} strokeWidth={2} />
          <div class="feature-content">
            <span class="feature-title">Live Weather & Location</span>
            <span class="feature-desc">Context-aware with real-time environmental data</span>
          </div>
        </div>
      </div>
    </section>

    <section class="login-panel">
      <div class="login-panel-header">
        <img src="/images/logo.svg" alt="sideBar" class="panel-logo" />
        <div class="login-wordmark">Login</div>
      </div>

      {#if loggedOut}
        <div class="login-success">You have been signed out.</div>
      {/if}

      {#if error}
        <div class="login-error">{error}</div>
      {/if}

      <form onsubmit={handleLogin}>
        <label>
          <span>Email</span>
          <input type="email" bind:value={email} autocomplete="email" required />
        </label>
        <label>
          <span>Password</span>
          <input type="password" bind:value={password} autocomplete="current-password" required />
        </label>
        <Button type="submit" disabled={loading} class="w-full">
          {loading ? 'Signing in…' : 'Sign in'}
        </Button>
      </form>
    </section>
    </div>
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
    background: var(--color-background);
  }

  .login-container {
    width: min(96vw, 1100px);
    display: flex;
    flex-direction: column;
    gap: 3rem;
  }

  .login-brand {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 1rem;
  }

  .brand-logo {
    width: 64px;
    height: 64px;
  }

  :global(.dark) .brand-logo {
    filter: invert(1);
  }

  .brand-wordmark {
    font-size: 2.5rem;
    font-weight: 600;
    letter-spacing: 0.02em;
    color: var(--color-foreground);
  }

  .login-grid {
    width: 100%;
    display: grid;
    grid-template-columns: minmax(0, 1.2fr) minmax(0, 0.8fr);
    gap: 2.5rem;
    align-items: stretch;
  }

  .login-wordmark {
    font-size: 2rem;
    font-weight: 600;
    letter-spacing: 0.02em;
    color: var(--color-foreground);
  }

  .login-hero {
    padding: 2.5rem 2.75rem;
    border-radius: 1rem;
    border: 1px solid var(--color-border);
    background: var(--color-card);
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
    position: relative;
  }

  .login-hero-title {
    display: flex;
    align-items: center;
    gap: 0.85rem;
    margin: 0 0 0.5rem;
    font-size: 2rem;
    font-weight: 600;
    color: var(--color-foreground);
  }

  .hero-logo {
    width: 44px;
    height: 44px;
  }

  :global(.dark) .hero-logo {
    filter: invert(1);
  }

  .login-tagline {
    margin: 0 0 1rem;
    font-size: 1.125rem;
    font-weight: 500;
    color: var(--color-primary);
  }

  .login-description {
    margin: 0 0 2rem;
    font-size: 1rem;
    color: var(--color-muted-foreground);
    line-height: 1.6;
  }

  /* Screenshot placeholder - uncomment when you add screenshot */
  /* .screenshot-placeholder {
    margin: 0 0 2rem;
    border-radius: 0.75rem;
    overflow: hidden;
    border: 1px solid var(--color-border);
    background: var(--color-muted);
  }

  .screenshot-placeholder img {
    width: 100%;
    height: auto;
    display: block;
  } */

  .login-features {
    display: grid;
    gap: 1rem;
  }

  .feature {
    display: flex;
    align-items: flex-start;
    gap: 0.75rem;
    padding: 0.75rem;
    border-radius: 0.5rem;
    transition: background-color 0.15s ease;
  }

  .feature:hover {
    background: var(--color-accent);
  }

  .feature :global(svg) {
    flex-shrink: 0;
    margin-top: 0.125rem;
    color: var(--color-primary);
  }

  .feature-content {
    display: flex;
    flex-direction: column;
    gap: 0.125rem;
    min-width: 0;
  }

  .feature-title {
    font-size: 0.875rem;
    font-weight: 500;
    color: var(--color-foreground);
  }

  .feature-desc {
    font-size: 0.8125rem;
    color: var(--color-muted-foreground);
    line-height: 1.4;
  }

  .login-panel {
    padding: 2.5rem 2.25rem;
    border-radius: 1rem;
    border: 1px solid var(--color-border);
    background: var(--color-card);
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
  }

  .login-panel-header {
    display: flex;
    align-items: center;
    gap: 0.75rem;
  }

  .login-success {
    padding: 0.75rem 0.9rem;
    border-radius: 0.6rem;
    background: var(--color-muted);
    border: 1px solid var(--color-border);
    color: var(--color-foreground);
    font-size: 0.9rem;
  }

  .panel-logo {
    width: 44px;
    height: 44px;
  }

  :global(.dark) .panel-logo {
    filter: invert(1);
  }

  form {
    display: flex;
    flex-direction: column;
    gap: 1.15rem;
  }

  label {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    font-size: 0.875rem;
    font-weight: 500;
    color: var(--color-foreground);
  }

  input {
    padding: 0.625rem 0.875rem;
    border: 1px solid var(--color-input);
    border-radius: 0.5rem;
    background: var(--color-background);
    color: var(--color-foreground);
    font-size: 0.9375rem;
    transition: border-color 0.15s ease, box-shadow 0.15s ease;
  }

  input:focus {
    outline: none;
    border-color: var(--color-ring);
    box-shadow: 0 0 0 3px var(--color-ring-offset);
  }

  .login-error {
    padding: 0.75rem 0.875rem;
    border-radius: 0.5rem;
    background: var(--color-destructive-foreground);
    color: var(--color-destructive);
    font-size: 0.875rem;
    border: 1px solid var(--color-destructive);
  }

  :global(.login-panel button.w-full) {
    margin-top: 0.25rem;
  }

  @media (max-width: 900px) {
    .login-container {
      gap: 2rem;
    }

    .brand-logo {
      width: 52px;
      height: 52px;
    }

    .brand-wordmark {
      font-size: 2rem;
    }

    .login-grid {
      grid-template-columns: 1fr;
    }

    .login-hero,
    .login-panel {
      padding: 2rem 1.75rem;
    }

    .login-hero-title {
      font-size: 1.75rem;
    }

    .login-tagline {
      font-size: 1rem;
    }

    .feature-desc {
      display: none;
    }
  }
</style>
