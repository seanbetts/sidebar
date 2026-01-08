<script lang="ts">
	import ConfirmDialog from './ConfirmDialog.svelte';

	export let open = false;
	export let title = 'Unable to complete action';
	export let message = 'Failed to create note. Please try again.';
	export let onConfirm: (() => void) | undefined;

	const handleConfirm = () => {
		if (onConfirm) {
			onConfirm();
			return;
		}
		open = false;
	};
</script>

<ConfirmDialog
	bind:open
	{title}
	description={message}
	confirmLabel="OK"
	showCancel={false}
	onConfirm={handleConfirm}
/>
