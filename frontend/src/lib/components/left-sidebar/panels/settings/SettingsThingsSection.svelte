<script lang="ts">
  import { Loader2 } from 'lucide-svelte';
  import { Button } from '$lib/components/ui/button';
  import { thingsAPI } from '$lib/services/api';

  let isInstalling = false;
  let isSavingToken = false;
  let errorMessage = '';
  let successMessage = '';
  let tokenValue = '';

  async function handleInstallBridge() {
    if (isInstalling) return;
    isInstalling = true;
    errorMessage = '';
    successMessage = '';
    try {
      const response = await fetch('/api/v1/things/bridges/install-script', { method: 'POST' });
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

  async function handleSaveToken() {
    if (isSavingToken) return;
    isSavingToken = true;
    errorMessage = '';
    successMessage = '';
    try {
      await thingsAPI.setUrlToken(tokenValue.trim());
      tokenValue = '';
      successMessage = 'Token saved on the active bridge.';
    } catch (error) {
      errorMessage = error instanceof Error ? error.message : 'Failed to save token.';
    } finally {
      isSavingToken = false;
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
  <div class="settings-field">
    <label for="things-url-token">Things URL auth token</label>
    <input
      id="things-url-token"
      type="password"
      autocomplete="off"
      bind:value={tokenValue}
      placeholder="Paste your Things URL token"
    />
    <div class="settings-actions">
      <Button onclick={handleSaveToken} disabled={isSavingToken || !tokenValue.trim()}>
        {#if isSavingToken}
          <Loader2 size={16} class="spin" />
          Saving...
        {:else}
          Save Token
        {/if}
      </Button>
    </div>
  </div>
  {#if successMessage}
    <div class="settings-success">{successMessage}</div>
  {/if}
  {#if errorMessage}
    <div class="settings-error">{errorMessage}</div>
  {/if}
</div>

<style>
  .settings-field {
    margin-top: 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .settings-field label {
    font-size: 0.85rem;
    color: var(--color-muted-foreground);
  }

  .settings-field input {
    padding: 0.5rem 0.75rem;
    border-radius: 0.5rem;
    border: 1px solid var(--color-border);
    background: var(--color-card);
    color: var(--color-foreground);
  }
</style>
