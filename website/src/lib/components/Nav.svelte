<script lang="ts">
  import { onMount } from 'svelte';

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
  <div class="nav-inner">
    <a href="/" class="brand" aria-label="sideBar home">
      <img src="/logo.svg" alt="" width="28" height="28" />
      <span>sideBar</span>
    </a>

    <div class="links">
      <a href="/about">About</a>
      <a href="https://docs.trysidebar.ai">Docs</a>
      <a href="https://app.trysidebar.ai" class="cta">Open App</a>
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
    border-bottom: 1px solid var(--color-border);
    background: color-mix(in oklch, var(--background) 85%, transparent);
    backdrop-filter: blur(12px);
    -webkit-backdrop-filter: blur(12px);
  }

  .nav-inner {
    max-width: 72rem;
    margin: 0 auto;
    padding: 0 1.5rem;
    height: 3.5rem;
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .brand {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    text-decoration: none;
    font-weight: 600;
    font-size: 1rem;
    color: var(--color-foreground);
  }

  .brand img {
    display: block;
  }

  .links {
    display: flex;
    align-items: center;
    gap: 1.5rem;
  }

  .links a:not(.cta) {
    font-size: 0.9rem;
    color: var(--color-muted-foreground);
    text-decoration: none;
    transition: color 0.15s;
  }

  .links a:not(.cta):hover {
    color: var(--color-foreground);
  }

  .cta {
    padding: 0.4rem 1rem;
    border-radius: 999px;
    border: 1px solid var(--color-border);
    background: var(--color-primary);
    color: var(--color-primary-foreground);
    font-size: 0.875rem;
    font-weight: 500;
    text-decoration: none;
  }

  .cta:hover {
    opacity: 0.85;
  }

  .theme-toggle {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 2rem;
    height: 2rem;
    border: none;
    background: none;
    color: var(--color-muted-foreground);
    cursor: pointer;
    border-radius: 0.375rem;
    transition: color 0.15s, background 0.15s;
  }

  .theme-toggle:hover {
    color: var(--color-foreground);
    background: var(--color-muted);
  }

  @media (max-width: 640px) {
    .links a:not(.cta) {
      display: none;
    }
  }
</style>
