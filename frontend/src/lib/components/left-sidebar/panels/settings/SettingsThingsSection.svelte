<script lang="ts">
  import { Loader2 } from 'lucide-svelte';
  import { Button } from '$lib/components/ui/button';

  let isInstalling = false;
  let errorMessage = '';
  let successMessage = '';

  async function handleInstallBridge() {
    if (isInstalling) return;
    isInstalling = true;
    errorMessage = '';
    successMessage = '';
    try {
      const response = await fetch('/api/things/bridges/install-script', { method: 'POST' });
      if (!response.ok) {
        throw new Error('Failed to generate install script');
      }
      const script = await response.text();
      const blob = new Blob([script], { type: 'text/plain' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = 'install-things-bridge.command';
      document.body.appendChild(link);
      link.click();
      link.remove();
      URL.revokeObjectURL(url);
      successMessage = 'Download started. Run the install script on this Mac to finish setup.';
    } catch (error) {
      errorMessage = error instanceof Error ? error.message : 'Failed to install bridge.';
    } finally {
      isInstalling = false;
    }
  }
</script>

<h3>Things Bridge</h3>
<p>Install the Things bridge so sideBar can read and update your tasks.</p>
<div class="settings-form">
  <div class="settings-actions">
    <Button onclick={handleInstallBridge} disabled={isInstalling}>
      {#if isInstalling}
        <Loader2 size={16} class="spin" />
        Preparing...
      {:else}
        Install Things Bridge
      {/if}
    </Button>
  </div>
  {#if successMessage}
    <div class="settings-success">{successMessage}</div>
  {/if}
  {#if errorMessage}
    <div class="settings-error">{errorMessage}</div>
  {/if}
</div>
