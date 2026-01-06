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
      return parsed.protocol === 'http:' || parsed.protocol === 'https:';
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
