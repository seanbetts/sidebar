<script lang="ts">
  import { onMount } from 'svelte';
  import PixelDivider from '$lib/components/PixelDivider.svelte';

  let isDark = $state(false);

  onMount(() => {
    isDark = document.documentElement.classList.contains('dark');
  });

  function toggleTheme() {
    isDark = !isDark;
    if (isDark) {
      document.documentElement.classList.add('dark');
      localStorage.setItem('theme', 'dark');
    } else {
      document.documentElement.classList.remove('dark');
      localStorage.setItem('theme', 'light');
    }
  }
</script>

<nav class="nav">
  <PixelDivider position="bottom" />
  <div class="nav-inner">
    <a href="/" class="brand" aria-label="sideBar home">
      <img src="/logo.svg" alt="" width="36" height="36" />
      <span class="brand-name">sideBar</span>
    </a>

    <div class="links">
      <a href="/">Home</a>
      <a href="/about">About</a>
      <a href="/pricing">Pricing</a>
      <a href="https://docs.trysidebar.ai">Docs</a>
      <a href="https://app.trysidebar.ai" class="cta">Request Early Access</a>
      <button class="theme-toggle" onclick={toggleTheme} aria-label="Toggle dark mode">
        {#if isDark}
          <!-- Sun icon -->
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/>
          </svg>
        {:else}
          <!-- Moon icon -->
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>
          </svg>
        {/if}
      </button>
    </div>
  </div>
</nav>

<style>
  .nav {
    position: sticky;
    top: 0;
    z-index: 50;
    background: var(--surface);
  }

  .nav-inner {
    max-width: 78rem;
    margin: 0 auto;
    padding: 0 1.5rem;
    height: 4.25rem;
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .brand {
    display: flex;
    align-items: center;
    gap: 0.8rem;
    text-decoration: none;
    font-family: var(--font-display);
    font-weight: var(--font-display-weight);
    font-size: 1.375rem;
    letter-spacing: var(--font-display-tracking);
    color: var(--color-foreground);
    line-height: var(--font-display-leading);
  }

  .brand img {
    display: block;
    width: 2.5rem;
    height: 2.5rem;
  }

  .brand-name {
    white-space: nowrap;
  }

  .links {
    display: flex;
    align-items: center;
    gap: 1.5rem;
  }

  .links a:not(.cta) {
    font-size: 0.95rem;
    font-weight: 500;
    color: var(--color-muted-foreground);
    text-decoration: none;
    transition: color 0.15s ease;
  }

  .links a:not(.cta):hover {
    color: var(--color-foreground);
  }

  .cta {
    padding: 0.5rem 0.95rem;
    border-radius: 999px;
    border: 1px solid var(--color-border);
    background: var(--color-primary);
    color: var(--color-primary-foreground);
    font-size: 0.875rem;
    font-weight: 600;
    text-decoration: none;
    white-space: nowrap;
    transition:
      background-color 0.15s ease,
      color 0.15s ease,
      border-color 0.15s ease;
  }

  .cta:hover {
    background: var(--color-foreground);
    border-color: var(--color-foreground);
    color: var(--color-background);
  }

  .theme-toggle {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 2rem;
    height: 2rem;
    border: 1px solid transparent;
    background: transparent;
    color: var(--color-muted-foreground);
    cursor: pointer;
    border-radius: 999px;
    transition:
      color 0.15s ease,
      background-color 0.15s ease,
      border-color 0.15s ease;
  }

  .theme-toggle:hover {
    color: var(--color-foreground);
    background: var(--color-secondary);
    border-color: var(--color-border);
  }

  @media (max-width: 640px) {
    .nav-inner {
      padding: 0 1rem;
      height: auto;
      min-height: 4.25rem;
      flex-wrap: wrap;
      row-gap: 0.75rem;
      padding-top: 0.75rem;
      padding-bottom: 0.75rem;
    }

    .brand-name {
      display: none;
    }

    .links {
      width: 100%;
      justify-content: space-between;
      gap: 0.75rem;
      flex-wrap: wrap;
    }

    .links a:not(.cta) {
      font-size: 0.9rem;
    }
  }
</style>
