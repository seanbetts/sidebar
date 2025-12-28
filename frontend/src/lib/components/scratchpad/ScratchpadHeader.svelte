<script lang="ts">
	export let isSaving = false;
	export let saveError: string | null = null;
</script>

<div class="scratchpad-header">
	<h2>✏️ Scratchpad</h2>
	{#if isSaving}
		<span class="status">Saving...</span>
	{:else if saveError}
		<span class="status error">{saveError}</span>
	{:else}
		<span class="status">Auto-save</span>
	{/if}
</div>

<style>
	.scratchpad-header {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: 1rem;
		border-bottom: 1px solid var(--color-border);
		padding-bottom: 0.5rem;
	}

	.scratchpad-header h2 {
		margin: 0;
		font-size: 1.1rem;
		font-weight: 600;
		color: var(--color-foreground);
	}

	.status {
		font-size: 0.75rem;
		color: var(--color-muted-foreground);
	}

	.status.error {
		color: var(--color-destructive);
	}
</style>
