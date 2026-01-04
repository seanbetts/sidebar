<script lang="ts">
  import { onMount } from 'svelte';
  import { fetchShortcutsPat, rotateShortcutsPat } from '$lib/components/left-sidebar/panels/settingsApi';
  import { logError } from '$lib/utils/errorHandling';

  let token = '';
  let isLoading = false;
  let isRotating = false;
  let error = '';
  let success = '';

  const loadToken = async () => {
    isLoading = true;
    error = '';
    success = '';
    try {
      token = await fetchShortcutsPat();
    } catch (err) {
      logError('Failed to load shortcuts token', err, {
        scope: 'SettingsShortcutsSection'
      });
      error = 'Failed to load shortcuts token.';
    } finally {
      isLoading = false;
    }
  };

  const handleRotate = async () => {
    isRotating = true;
    error = '';
    success = '';
    try {
      token = await rotateShortcutsPat();
      success = 'Token regenerated.';
    } catch (err) {
      logError('Failed to rotate shortcuts token', err, {
        scope: 'SettingsShortcutsSection'
      });
      error = 'Failed to rotate shortcuts token.';
    } finally {
      isRotating = false;
    }
  };

  const handleCopy = async () => {
    if (!token) return;
    try {
      await navigator.clipboard.writeText(token);
      success = 'Token copied to clipboard.';
    } catch (err) {
      logError('Failed to copy shortcuts token', err, {
        scope: 'SettingsShortcutsSection'
      });
      error = 'Failed to copy token.';
    }
  };

  onMount(() => {
    void loadToken();
  });
</script>

<h3>Shortcuts</h3>
<p>Use this token in Apple Shortcuts to authorize quick capture requests.</p>
<div class="settings-form">
  {#if error}
    <div class="settings-error">{error}</div>
  {/if}
  {#if success}
    <div class="settings-success">{success}</div>
  {/if}
  <label class="settings-label">
    Token
    <input class="settings-input" type="text" bind:value={token} readonly />
  </label>
  <div class="settings-actions">
    <button class="settings-button secondary" on:click={handleCopy} disabled={!token || isLoading}>
      Copy
    </button>
    <button class="settings-button" on:click={handleRotate} disabled={isRotating}>
      {isRotating ? 'Regenerating...' : 'Regenerate'}
    </button>
  </div>
  <div class="settings-meta">Regenerating invalidates the previous token.</div>
</div>
