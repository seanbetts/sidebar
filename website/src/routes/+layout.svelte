<script lang="ts">
  import '../app.css';
  import Nav from '$lib/components/Nav.svelte';
  import Footer from '$lib/components/Footer.svelte';

  let { children } = $props();
</script>

<Nav />
<main>
  {@render children()}
</main>
<Footer />

<style>
  main {
    min-height: calc(100vh - 3.5rem);
  }

  :global(.page-inner h1) {
    font-size: clamp(2.25rem, 4vw, 3.5rem);
    font-weight: var(--font-display-weight);
    letter-spacing: var(--font-display-tracking);
    line-height: var(--font-display-leading);
    margin: 0 0 0.25rem;
  }

  :global(.page-inner h2) {
    font-size: 1.125rem;
    font-weight: 700;
    letter-spacing: -0.03em;
    line-height: 1;
    margin: 2rem 0 0.75rem;
  }

  :global(.page-inner h3) {
    font-size: 1rem;
    font-weight: 700;
    letter-spacing: -0.02em;
    line-height: 1.05;
    margin: 1.5rem 0 0.5rem;
  }

  :global(.page-inner p) {
    font-size: 1rem;
    line-height: 1.7;
    color: var(--color-muted-foreground);
    margin: 0 0 1rem;
  }

  :global(.page-inner ul) {
    margin: 0 0 1rem;
    padding-left: 1.5rem;
  }

  :global(.page-inner li) {
    font-size: 1rem;
    line-height: 1.7;
    color: var(--color-muted-foreground);
    margin-bottom: 0.25rem;
  }

  :global(.page-inner a) {
    color: var(--color-foreground);
    text-decoration: underline;
    text-underline-offset: 3px;
  }

  :global(.page-inner a:hover) {
    color: var(--color-muted-foreground);
  }
</style>
