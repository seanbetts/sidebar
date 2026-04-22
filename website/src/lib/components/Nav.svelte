<script lang="ts">
  import { onMount } from 'svelte';
  import PixelDivider from '$lib/components/PixelDivider.svelte';

  const THEME_MEDIA_QUERY = '(prefers-color-scheme: dark)';

  let isDark = $state(false);

  onMount(() => {
    const applyTheme = (theme: 'light' | 'dark', persist: boolean) => {
      isDark = theme === 'dark';
      document.documentElement.classList.toggle('dark', isDark);
      if (persist) {
        localStorage.setItem('theme', theme);
      }
    };

    const stored = localStorage.getItem('theme');
    const initialTheme =
      stored === 'light' || stored === 'dark'
        ? stored
        : window.matchMedia?.(THEME_MEDIA_QUERY).matches
          ? 'dark'
          : 'light';
    applyTheme(initialTheme, false);

    const mediaQuery = window.matchMedia?.(THEME_MEDIA_QUERY);
    const handleChange = () => {
      if (!localStorage.getItem('theme')) {
        applyTheme(mediaQuery?.matches ? 'dark' : 'light', false);
      }
    };

    if (typeof mediaQuery?.addEventListener === 'function') {
      mediaQuery.addEventListener('change', handleChange);
      return () => mediaQuery.removeEventListener('change', handleChange);
    }

    if (typeof mediaQuery?.addListener === 'function') {
      mediaQuery.addListener(handleChange);
      return () => mediaQuery.removeListener(handleChange);
    }
  });

  function toggleTheme() {
    const nextTheme = isDark ? 'light' : 'dark';
    isDark = nextTheme === 'dark';
    document.documentElement.classList.toggle('dark', isDark);
    localStorage.setItem('theme', nextTheme);
  }
</script>

<nav class="nav">
  <PixelDivider position="bottom" />
  <div class="nav-inner">
    <a href="/" class="brand" aria-label="sideBar home">
      <span class="brand-mark" aria-hidden="true">
        <img
          class="brand-mark__asset brand-mark__asset--light"
          src="/logo-light.png"
          alt=""
          width="40"
          height="40"
        />
        <img
          class="brand-mark__asset brand-mark__asset--dark"
          src="/logo-dark.png"
          alt=""
          width="40"
          height="40"
        />
      </span>
      <span class="brand-name">sideBar</span>
    </a>

    <div class="links">
      <a href="/">Home</a>
      <a href="/about">About</a>
      <a href="/pricing">Pricing</a>
      <a href="https://docs.trysidebar.ai">Docs</a>
      <a href="/early-access" class="cta">Join Early Access List</a>
      <button
        class="theme-toggle"
        onclick={toggleTheme}
        aria-label={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
      >
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
    isolation: isolate;
    background: var(--surface-glass-fallback);
    border-bottom: 1px solid var(--glass-stroke);
    box-shadow: 0 1.25rem 2.5rem -2rem var(--shadow-color);
    -webkit-backdrop-filter: saturate(180%) blur(1.5rem);
    backdrop-filter: saturate(180%) blur(1.5rem);
  }

  .nav-inner {
    position: relative;
    z-index: 2;
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
    gap: 0.4rem;
    text-decoration: none;
    font-family: var(--font-display);
    font-weight: var(--font-display-weight);
    font-size: 1.375rem;
    letter-spacing: var(--font-display-tracking);
    color: var(--color-foreground);
    line-height: var(--font-display-leading);
  }

  .brand-mark {
    position: relative;
    display: inline-grid;
    place-items: center;
    width: 2.5rem;
    height: 2.5rem;
    flex: 0 0 auto;
  }

  .brand-mark__asset {
    grid-area: 1 / 1;
    display: block;
    width: 100%;
    height: 100%;
  }

  .brand-mark__asset--dark {
    display: none;
  }

  :global(.dark) .brand-mark__asset--light {
    display: none;
  }

  :global(.dark) .brand-mark__asset--dark {
    display: block;
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

  @supports ((-webkit-backdrop-filter: blur(1px)) or (backdrop-filter: blur(1px))) {
    .nav {
      background: var(--surface-glass);
    }
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
