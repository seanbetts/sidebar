<script lang="ts">
  import { onMount } from 'svelte';
  import { Button } from '$lib/components/ui/button';
  import { clearCaches, clearInFlight, clearMemoryCache, getCacheStats } from '$lib/utils/cache';
  import DeleteDialogController from '$lib/components/files/DeleteDialogController.svelte';

  let cacheStats = { count: 0, totalSize: 0, oldestAge: 0 };
  let deleteDialog: { openDialog: (name: string) => void } | null = null;

  function loadCacheStats() {
    cacheStats = getCacheStats();
  }

  function requestClearCache() {
    deleteDialog?.openDialog('cached data');
  }

  function handleClearCache(): boolean {
      clearCaches();
      clearMemoryCache();
      clearInFlight();
      loadCacheStats();
      return true;
  }

  onMount(loadCacheStats);
</script>

<h3>Storage & Cache</h3>
<p>Manage cached data used to speed up the sidebar and history views.</p>
<div class="settings-form">
  <div class="cache-stats">
    <p>Cached items: <strong>{cacheStats.count}</strong></p>
    <p>Cache size: <strong>{(cacheStats.totalSize / 1024).toFixed(2)} KB</strong></p>
    <p>Oldest cache: <strong>{(cacheStats.oldestAge / 1000 / 60).toFixed(0)} minutes ago</strong></p>
  </div>
  <div class="settings-actions">
    <Button variant="destructive" onclick={requestClearCache}>Clear cache</Button>
  </div>
</div>

<DeleteDialogController
  bind:this={deleteDialog}
  itemType="cache"
  onConfirm={handleClearCache}
/>

<style>
  .cache-stats {
    margin: 0.75rem 0;
    padding: 0.75rem;
    border-radius: 0.65rem;
    background: var(--color-muted);
  }

  .cache-stats p {
    margin: 0.35rem 0;
    font-size: 0.85rem;
    color: var(--color-muted-foreground);
  }
</style>
