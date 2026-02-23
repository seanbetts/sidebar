<script lang="ts">
	import { Trash2, X } from 'lucide-svelte';
	import type { IngestionListItem } from '$lib/types/ingestion';
	import { buildIngestionStatusMessage } from '$lib/utils/ingestionStatus';
	import IngestionDetailModal from '$lib/components/files/IngestionDetailModal.svelte';
	import { ingestionAPI } from '$lib/services/api';
	import { ingestionStore } from '$lib/stores/ingestion';
	import { logError } from '$lib/utils/errorHandling';

	export let activeItems: IngestionListItem[] = [];
	export let failedItems: IngestionListItem[] = [];
	export let onCancel: (fileId: string) => void;
	export let onClearFailure: (fileId: string) => void;

	let detailItem: IngestionListItem | null = null;
	let isDetailOpen = false;

	function openDetail(item: IngestionListItem) {
		detailItem = item;
		isDetailOpen = true;
	}

	async function handleDetailCancel(fileId: string) {
		try {
			await ingestionAPI.cancel(fileId);
			const meta = await ingestionAPI.get(fileId);
			ingestionStore.upsertItem({
				file: meta.file,
				job: meta.job,
				recommended_viewer: meta.recommended_viewer
			});
		} catch (error) {
			logError('Failed to cancel ingestion from status center', error, {
				scope: 'IngestionStatusCenter.detailCancel',
				fileId
			});
			throw error;
		}
	}

	async function handleDetailRetry(fileId: string) {
		try {
			await ingestionAPI.resume(fileId);
			const meta = await ingestionAPI.get(fileId);
			ingestionStore.upsertItem({
				file: meta.file,
				job: meta.job,
				recommended_viewer: meta.recommended_viewer
			});
		} catch (error) {
			logError('Failed to retry ingestion from status center', error, {
				scope: 'IngestionStatusCenter.detailRetry',
				fileId
			});
			throw error;
		}
	}
</script>

<div class="ingestion-center">
	{#if activeItems.length > 0}
		<div class="ingestion-group">
			<div class="ingestion-group-title">In Progress</div>
			{#each activeItems as item (item.file.id)}
				<div
					class="ingestion-row ingestion-row-clickable"
					role="button"
					tabindex="0"
					onclick={() => openDetail(item)}
					onkeydown={(e) => e.key === 'Enter' && openDetail(item)}
				>
					<div class="ingestion-details">
						<span class="ingestion-filename">{item.file.filename_original}</span>
						<span class="ingestion-status">{buildIngestionStatusMessage(item.job)}</span>
					</div>
					<button
						class="ingestion-action"
						onclick={(e) => {
							e.stopPropagation();
							onCancel(item.file.id);
						}}
						aria-label="Cancel upload"
					>
						<X size={14} />
					</button>
				</div>
			{/each}
		</div>
	{/if}

	{#if failedItems.length > 0}
		<div class="ingestion-group">
			<div class="ingestion-group-title">Failed</div>
			{#each failedItems as item (item.file.id)}
				<div
					class="ingestion-row ingestion-row-clickable"
					role="button"
					tabindex="0"
					onclick={() => openDetail(item)}
					onkeydown={(e) => e.key === 'Enter' && openDetail(item)}
				>
					<div class="ingestion-details">
						<span class="ingestion-filename">{item.file.filename_original}</span>
						<span class="ingestion-status">{item.job.error_message || 'Upload failed'}</span>
					</div>
					<button
						class="ingestion-action"
						onclick={(e) => {
							e.stopPropagation();
							onClearFailure(item.file.id);
						}}
						aria-label="Clear failed upload"
					>
						<Trash2 size={14} />
					</button>
				</div>
			{/each}
		</div>
	{/if}
</div>

<IngestionDetailModal
	bind:open={isDetailOpen}
	item={detailItem}
	onClose={() => {
		isDetailOpen = false;
		detailItem = null;
	}}
	onCancel={handleDetailCancel}
	onRetry={handleDetailRetry}
/>

<style>
	.ingestion-center {
		display: flex;
		flex-direction: column;
		gap: 0.7rem;
		padding: 0.25rem;
		min-width: min(420px, 80vw);
		max-width: min(480px, 90vw);
	}

	.ingestion-group {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}

	.ingestion-group-title {
		font-size: 0.7rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-muted-foreground);
		font-weight: 600;
		padding: 0 0.2rem;
	}

	.ingestion-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.5rem;
		border: 1px solid var(--color-border);
		border-radius: 0.6rem;
		padding: 0.45rem 0.55rem;
		background: color-mix(in oklab, var(--color-card) 85%, transparent);
	}

	.ingestion-row-clickable {
		cursor: pointer;
		transition: border-color 0.15s;
	}

	.ingestion-row-clickable:hover {
		border-color: var(--color-foreground);
	}

	.ingestion-details {
		display: flex;
		flex-direction: column;
		min-width: 0;
		gap: 0.1rem;
	}

	.ingestion-filename {
		font-size: 0.78rem;
		font-weight: 600;
		color: var(--color-foreground);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.ingestion-status {
		font-size: 0.72rem;
		color: var(--color-muted-foreground);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.ingestion-action {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 1.8rem;
		height: 1.8rem;
		border: none;
		border-radius: 0.4rem;
		background: transparent;
		color: var(--color-muted-foreground);
		cursor: pointer;
	}

	.ingestion-action:hover {
		background: var(--color-accent);
		color: var(--color-foreground);
	}
</style>
