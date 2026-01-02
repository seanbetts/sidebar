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
		padding-right: 1rem;
		overflow: hidden;
		width: 100%;
		max-width: 100%;
		box-sizing: border-box;
	}

	.scratchpad-header h2 {
		margin: 0;
		font-size: 1.1rem;
		font-weight: 600;
		color: var(--color-foreground);
		min-width: 0;
		flex: 1 1 auto;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.status {
		font-size: 0.75rem;
		color: var(--color-muted-foreground);
		flex-shrink: 1;
		min-width: 0;
		max-width: 45%;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		text-align: right;
	}

	.status.error {
		color: var(--color-destructive);
	}
</style>
