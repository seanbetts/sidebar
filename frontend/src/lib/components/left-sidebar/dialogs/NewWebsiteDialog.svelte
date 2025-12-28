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
</script>

<TextInputDialog
  bind:open
  title="Save a website"
  description="Paste a URL to save it to your archive."
  placeholder="https://example.com"
  bind:value
  {isBusy}
  busyLabel="Saving..."
  confirmLabel="Save website"
  onConfirm={onConfirm}
  onCancel={handleCancel}
/>
