<script lang="ts">
	import { Loader2 } from 'lucide-svelte';
	import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';

	export let open = false;
	export let title = 'Create item';
	export let description = '';
	export let placeholder = '';
	export let value = '';
	export let confirmLabel = 'Confirm';
	export let cancelLabel = 'Cancel';
	export let busyLabel = 'Working...';
	export let isBusy = false;
	export let inputType = 'text';
	export let disableWhenEmpty = true;
	export let isValid = true;
	export let onConfirm: (() => void) | undefined = undefined;
	export let onCancel: (() => void) | undefined = undefined;

	let inputElement: HTMLInputElement | null = null;
	$: isDisabled = isBusy || (disableWhenEmpty && !value.trim()) || !isValid;
</script>

<AlertDialog.Root bind:open>
	<AlertDialog.Content
		onOpenAutoFocus={(event) => {
			event.preventDefault();
			inputElement?.focus();
			inputElement?.select();
		}}
	>
		<AlertDialog.Header>
			<AlertDialog.Title>{title}</AlertDialog.Title>
			{#if description}
				<AlertDialog.Description>{description}</AlertDialog.Description>
			{/if}
		</AlertDialog.Header>
		<div class="py-2">
			<input
				class="w-full rounded-md border bg-background px-3 py-2 text-sm shadow-sm outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
				type={inputType}
				{placeholder}
				bind:this={inputElement}
				bind:value
				disabled={isBusy}
				on:keydown={(event) => {
					if (event.key === 'Enter' && !isDisabled && onConfirm) {
						onConfirm();
					}
				}}
			/>
		</div>
		<AlertDialog.Footer>
			<AlertDialog.Cancel disabled={isBusy} onclick={() => onCancel?.()}>
				{cancelLabel}
			</AlertDialog.Cancel>
			<AlertDialog.Action disabled={isDisabled} onclick={() => onConfirm?.()}>
				{#if isBusy}
					<span class="inline-flex items-center gap-2">
						<Loader2 size={14} class="animate-spin" />
						{busyLabel}
					</span>
				{:else}
					{confirmLabel}
				{/if}
			</AlertDialog.Action>
		</AlertDialog.Footer>
	</AlertDialog.Content>
</AlertDialog.Root>
