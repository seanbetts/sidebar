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
  title="Create a new folder"
  description="Folders help organize your notes."
  placeholder="Folder name"
  bind:value
  {isBusy}
  busyLabel="Creating..."
  confirmLabel="Create folder"
  onConfirm={onConfirm}
  onCancel={handleCancel}
/>
