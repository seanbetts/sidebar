<script lang="ts">
	import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';

	export let open = false;
	export let value = '';
	export let onConfirm: () => void;
	export let onCancel: () => void;

	let inputRef: HTMLInputElement | null = null;
</script>

<AlertDialog.Root bind:open>
	<AlertDialog.Content
		onOpenAutoFocus={(event) => {
			event.preventDefault();
			inputRef?.focus();
			inputRef?.select();
		}}
	>
		<AlertDialog.Header>
			<AlertDialog.Title>Rename website</AlertDialog.Title>
			<AlertDialog.Description>Update the website title.</AlertDialog.Description>
		</AlertDialog.Header>
		<div class="py-2">
			<input
				class="w-full rounded-md border bg-background px-3 py-2 text-sm shadow-sm outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
				type="text"
				placeholder="Website title"
				bind:this={inputRef}
				bind:value
				on:keydown={(event) => {
					if (event.key === 'Enter') onConfirm();
				}}
			/>
		</div>
		<AlertDialog.Footer>
			<AlertDialog.Cancel onclick={onCancel}>Cancel</AlertDialog.Cancel>
			<AlertDialog.Action disabled={!value.trim()} onclick={onConfirm}>Rename</AlertDialog.Action>
		</AlertDialog.Footer>
	</AlertDialog.Content>
</AlertDialog.Root>
