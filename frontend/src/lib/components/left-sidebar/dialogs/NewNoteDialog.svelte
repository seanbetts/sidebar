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
  title="Create a new note"
  description="Pick a name. We'll save it as a markdown file."
  placeholder="Note name"
  bind:value
  {isBusy}
  busyLabel="Creating..."
  confirmLabel="Create note"
  onConfirm={onConfirm}
  onCancel={handleCancel}
/>
