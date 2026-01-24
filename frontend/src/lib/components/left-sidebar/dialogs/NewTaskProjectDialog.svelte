<script lang="ts">
	import { Loader2 } from 'lucide-svelte';
	import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';

	export let open = false;
	export let title = 'New project';
	export let description = 'Name your project and choose an optional group.';
	export let value = '';
	export let groupId = '';
	export let groups: Array<{ id: string; title: string }> = [];
	export let confirmLabel = 'Create project';
	export let cancelLabel = 'Cancel';
	export let busyLabel = 'Creating...';
	export let isBusy = false;
	export let onConfirm: (() => void) | undefined = undefined;
	export let onCancel: (() => void) | undefined = undefined;

	let inputElement: HTMLInputElement | null = null;
	$: isDisabled = isBusy || !value.trim();
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
				placeholder="Project name"
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
		<div class="pb-2">
			<select
				class="w-full rounded-md border bg-background px-3 py-2 text-sm shadow-sm outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
				bind:value={groupId}
				disabled={isBusy}
			>
				<option value="">No group</option>
				{#each groups as group}
					<option value={group.id}>{group.title}</option>
				{/each}
			</select>
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
