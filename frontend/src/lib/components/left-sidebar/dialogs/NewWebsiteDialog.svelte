<script lang="ts">
  import TextInputDialog from './TextInputDialog.svelte';

  export let open = false;
  export let value = '';
  export let isBusy = false;
  export let onConfirm: (() => void) | undefined;
  export let onCancel: (() => void) | undefined;

  const handleCancel = () => {
    if (onCancel) {
      onCancel();
      return;
    }
    open = false;
  };

  const isValidUrl = (input: string) => {
    const trimmed = input.trim();
    if (!trimmed) return false;
    const candidate = /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
    try {
      const parsed = new URL(candidate);
      if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return false;
      const host = parsed.hostname.toLowerCase();
      if (!host) return false;
      if (host === 'localhost') return false;
      if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host)) return false;
      if (host.includes(':')) return false;
      if (!host.includes('.')) return false;
      const labels = host.split('.');
      if (labels.some(label => !label || !/^[a-z0-9-]+$/.test(label) || label.startsWith('-') || label.endsWith('-'))) {
        return false;
      }
      const tld = labels[labels.length - 1];
      if (!/^[a-z]{2,24}$/.test(tld)) return false;
      return true;
    } catch {
      return false;
    }
  };

  $: isUrlValid = isValidUrl(value);
</script>

<TextInputDialog
  bind:open
  title="Save a website"
  description="Paste a URL to save it to your archive."
  placeholder="https://example.com"
  inputType="url"
  bind:value
  isValid={isUrlValid}
  {isBusy}
  busyLabel="Saving..."
  confirmLabel="Save website"
  onConfirm={onConfirm}
  onCancel={handleCancel}
/>
