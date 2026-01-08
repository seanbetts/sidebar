<script lang="ts">
	import NoteDeleteDialog from '$lib/components/files/NoteDeleteDialog.svelte';
	import { logError } from '$lib/utils/errorHandling';

	export let itemType = 'item';
	export let onConfirm: (() => boolean | Promise<boolean> | void | Promise<void>) | undefined =
		undefined;

	let open = false;
	let itemName = '';

	export function openDialog(name: string) {
		itemName = name;
		open = true;
	}

	async function handleConfirm() {
		try {
			const result = await onConfirm?.();
			if (result === false) return;
			open = false;
		} catch (error) {
			logError('Delete failed', error, { scope: 'DeleteDialogController', itemType });
		}
	}
</script>

<NoteDeleteDialog
	bind:open
	{itemType}
	{itemName}
	onConfirm={handleConfirm}
	onCancel={() => (open = false)}
/>
