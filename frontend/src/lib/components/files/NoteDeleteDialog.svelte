<script lang="ts">
	import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';
	import { buttonVariants } from '$lib/components/ui/button/index.js';

	export let open = false;
	export let itemType = 'note';
	export let itemName = '';
	export let onConfirm: (() => void) | undefined = undefined;
	export let onCancel: (() => void) | undefined = undefined;

	let deleteButton: HTMLButtonElement | null = null;
</script>

<AlertDialog.Root bind:open>
	<AlertDialog.Content
		onOpenAutoFocus={(event) => {
			event.preventDefault();
			deleteButton?.focus();
		}}
	>
		<AlertDialog.Header>
			<AlertDialog.Title>Delete {itemType}?</AlertDialog.Title>
			<AlertDialog.Description>
				This will permanently delete "{itemName}". This action cannot be undone.
			</AlertDialog.Description>
		</AlertDialog.Header>
		<AlertDialog.Footer>
			<AlertDialog.Cancel onclick={() => onCancel?.()}>Cancel</AlertDialog.Cancel>
			<AlertDialog.Action
				class={buttonVariants({ variant: 'destructive' })}
				bind:ref={deleteButton}
				onclick={() => onConfirm?.()}
			>
				Delete
			</AlertDialog.Action>
		</AlertDialog.Footer>
	</AlertDialog.Content>
</AlertDialog.Root>
