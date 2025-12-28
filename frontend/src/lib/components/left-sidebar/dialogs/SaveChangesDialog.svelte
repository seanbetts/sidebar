<script lang="ts">
  import ConfirmDialog from './ConfirmDialog.svelte';

  export let open = false;
  export let onConfirm: (() => void) | undefined;
  export let onCancel: (() => void) | undefined;

  const handleConfirm = () => {
    if (onConfirm) {
      onConfirm();
      return;
    }
    open = false;
  };

  const handleCancel = () => {
    if (onCancel) {
      onCancel();
      return;
    }
    open = false;
  };
</script>

<ConfirmDialog
  bind:open
  title="Save changes?"
  description="You have unsaved changes. Would you like to save them before switching notes?"
  confirmLabel="Save changes"
  cancelLabel="Don't save"
  onConfirm={handleConfirm}
  onCancel={handleCancel}
/>
