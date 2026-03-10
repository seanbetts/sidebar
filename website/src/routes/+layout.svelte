<script lang="ts">
  import '../app.css';
  import Nav from '$lib/components/Nav.svelte';
  import Footer from '$lib/components/Footer.svelte';
  import type { Snippet } from 'svelte';

  let { children }: { children: Snippet } = $props();
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
</style>
