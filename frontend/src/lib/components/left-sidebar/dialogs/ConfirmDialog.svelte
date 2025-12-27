<script lang="ts">
  import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';

  export let open = false;
  export let title = 'Confirm';
  export let description = '';
  export let confirmLabel = 'OK';
  export let cancelLabel = 'Cancel';
  export let showCancel = true;
  export let onConfirm: (() => void) | undefined = undefined;
  export let onCancel: (() => void) | undefined = undefined;
</script>

<AlertDialog.Root bind:open>
  <AlertDialog.Content>
    <AlertDialog.Header>
      <AlertDialog.Title>{title}</AlertDialog.Title>
      {#if description}
        <AlertDialog.Description>{description}</AlertDialog.Description>
      {/if}
    </AlertDialog.Header>
    <AlertDialog.Footer>
      {#if showCancel}
        <AlertDialog.Cancel onclick={() => onCancel?.()}>{cancelLabel}</AlertDialog.Cancel>
      {/if}
      <AlertDialog.Action onclick={() => onConfirm?.()}>{confirmLabel}</AlertDialog.Action>
    </AlertDialog.Footer>
  </AlertDialog.Content>
</AlertDialog.Root>
