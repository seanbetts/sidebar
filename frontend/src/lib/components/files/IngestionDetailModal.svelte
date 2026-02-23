<script lang="ts">
	import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';
	import { buildIngestionStatusMessage } from '$lib/utils/ingestionStatus';
	import type { IngestionListItem } from '$lib/types/ingestion';

	export let open = false;
	export let item: IngestionListItem | null = null;
	export let onClose: () => void;
	export let onCancel: (fileId: string) => Promise<void>;
	export let onRetry: (fileId: string) => Promise<void>;

	const stageOrder = [
		'uploading',
		'queued',
		'validating',
		'converting',
		'extracting',
		'ai_md',
		'thumb',
		'finalizing',
		'ready'
	];

	function getProgress(stage: string | null, progress: number | null | undefined): number {
		if (!stage) return 0;
		if (stage === 'uploading' && typeof progress === 'number') {
			return Math.round(progress);
		}
		const index = stageOrder.indexOf(stage);
		if (index < 0) return 0;
		return Math.round((index / (stageOrder.length - 1)) * 100);
	}

	function formatBytes(bytes?: number): string {
		if (!bytes) return '';
		if (bytes < 1024) return `${bytes} B`;
		if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
		return `${(bytes / 1048576).toFixed(1)} MB`;
	}

	let cancelling = false;
	let retrying = false;
	let actionError = '';

	$: job = item?.job;
	$: status = job?.status ?? null;
	$: stage = job?.stage ?? status;
	$: progress = getProgress(stage, job?.progress);
	$: statusMessage = buildIngestionStatusMessage(job);
	$: isFailed = status === 'failed';
	$: isProcessing = status === 'processing' || status === 'paused' || status === 'queued';
	$: isReady = status === 'ready';
	$: mimeType = item?.file.mime_original ?? '';
	$: fileSize = formatBytes(item?.file.size_bytes);

	$: if (!open) {
		cancelling = false;
		retrying = false;
		actionError = '';
	}

	async function handleCancel() {
		if (!item) return;
		cancelling = true;
		actionError = '';
		try {
			await onCancel(item.file.id);
			onClose();
		} catch (err) {
			actionError = err instanceof Error ? err.message : 'Failed to cancel';
		} finally {
			cancelling = false;
		}
	}

	async function handleRetry() {
		if (!item) return;
		retrying = true;
		actionError = '';
		try {
			await onRetry(item.file.id);
		} catch (err) {
			actionError = err instanceof Error ? err.message : 'Failed to retry';
		} finally {
			retrying = false;
		}
	}
</script>

<AlertDialog.Root bind:open>
	<AlertDialog.Content class="ingestion-detail-dialog">
		{#if item}
			<AlertDialog.Header>
				<AlertDialog.Title class="ingestion-detail-title">
					{item.file.filename_original}
				</AlertDialog.Title>
				<AlertDialog.Description>
					<div class="ingestion-detail-meta">
						{#if mimeType}
							<span class="ingestion-meta-badge">{mimeType}</span>
						{/if}
						{#if fileSize}
							<span class="ingestion-meta-size">{fileSize}</span>
						{/if}
					</div>
				</AlertDialog.Description>
			</AlertDialog.Header>

			<div class="ingestion-detail-body">
				{#if !isReady}
					<div class="ingestion-progress-section">
						<div class="ingestion-progress-header">
							<span class="ingestion-stage-label">{statusMessage}</span>
							<span class="ingestion-progress-pct">{progress}%</span>
						</div>
						<div class="ingestion-progress-track">
							<div
								class="ingestion-progress-fill"
								class:ingestion-progress-failed={isFailed}
								style={`width: ${isFailed ? 100 : progress}%`}
							></div>
						</div>
					</div>
				{/if}

				{#if isFailed}
					<div class="ingestion-error-block">
						<div class="ingestion-error-label">Error</div>
						<div class="ingestion-error-message">
							{job?.user_message || job?.error_message || 'Processing failed.'}
						</div>
						{#if job?.error_code}
							<div class="ingestion-error-code">Code: {job.error_code}</div>
						{/if}
					</div>
				{/if}

				{#if isReady}
					<div class="ingestion-ready-msg">File is ready.</div>
				{/if}

				{#if isProcessing}
					<div class="ingestion-stages">
						{#each stageOrder.filter((s) => s !== 'uploading' && s !== 'ready') as s}
							{@const idx = stageOrder.indexOf(s)}
							{@const currentIdx = stageOrder.indexOf(stage ?? '')}
							{@const done = idx < currentIdx}
							{@const active = s === stage}
							<div class="ingestion-stage" class:done class:active>
								<span class="ingestion-stage-dot"></span>
								<span class="ingestion-stage-name">{s.replace(/_/g, ' ')}</span>
							</div>
						{/each}
					</div>
				{/if}

				{#if actionError}
					<div class="ingestion-action-error">{actionError}</div>
				{/if}
			</div>

			<AlertDialog.Footer>
				<AlertDialog.Cancel onclick={onClose}>
					{isReady ? 'Close' : 'Dismiss'}
				</AlertDialog.Cancel>
				{#if isFailed}
					<button
						class="ingestion-action-btn ingestion-action-retry"
						onclick={handleRetry}
						disabled={retrying}
					>
						{retrying ? 'Retrying…' : 'Retry'}
					</button>
				{:else if isProcessing}
					<button
						class="ingestion-action-btn ingestion-action-cancel"
						onclick={handleCancel}
						disabled={cancelling}
					>
						{cancelling ? 'Cancelling…' : 'Cancel upload'}
					</button>
				{/if}
			</AlertDialog.Footer>
		{/if}
	</AlertDialog.Content>
</AlertDialog.Root>

<style>
	:global(.ingestion-detail-dialog) {
		max-width: 480px !important;
		width: min(96vw, 480px) !important;
	}

	.ingestion-detail-meta {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		margin-top: 0.25rem;
		flex-wrap: wrap;
	}

	.ingestion-meta-badge {
		display: inline-block;
		padding: 0.15rem 0.5rem;
		border-radius: 999px;
		font-size: 0.7rem;
		border: 1px solid var(--color-border);
		background: var(--color-secondary);
		color: var(--color-muted-foreground);
	}

	.ingestion-meta-size {
		font-size: 0.78rem;
		color: var(--color-muted-foreground);
	}

	.ingestion-detail-body {
		display: flex;
		flex-direction: column;
		gap: 1rem;
		margin-top: 0.75rem;
	}

	.ingestion-progress-section {
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}

	.ingestion-progress-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.5rem;
	}

	.ingestion-stage-label {
		font-size: 0.82rem;
		color: var(--color-foreground);
		font-weight: 500;
	}

	.ingestion-progress-pct {
		font-size: 0.78rem;
		color: var(--color-muted-foreground);
	}

	.ingestion-progress-track {
		height: 6px;
		background: var(--color-border);
		border-radius: 999px;
		overflow: hidden;
	}

	.ingestion-progress-fill {
		height: 100%;
		background: var(--color-sidebar-primary);
		border-radius: 999px;
		transition: width 0.3s ease;
	}

	.ingestion-progress-failed {
		background: var(--color-destructive);
	}

	.ingestion-error-block {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
		padding: 0.75rem;
		border-radius: 0.75rem;
		background: color-mix(in oklab, var(--color-destructive) 10%, transparent);
		border: 1px solid color-mix(in oklab, var(--color-destructive) 25%, transparent);
	}

	.ingestion-error-label {
		font-size: 0.7rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-destructive);
	}

	.ingestion-error-message {
		font-size: 0.85rem;
		color: var(--color-foreground);
		line-height: 1.4;
	}

	.ingestion-error-code {
		font-size: 0.72rem;
		color: var(--color-muted-foreground);
		font-family: monospace;
	}

	.ingestion-ready-msg {
		font-size: 0.85rem;
		color: #2f8a4d;
		font-weight: 500;
	}

	.ingestion-stages {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}

	.ingestion-stage {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		font-size: 0.78rem;
		color: var(--color-muted-foreground);
		text-transform: capitalize;
	}

	.ingestion-stage.done {
		color: var(--color-foreground);
	}

	.ingestion-stage.active {
		color: var(--color-foreground);
		font-weight: 600;
	}

	.ingestion-stage-dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
		background: var(--color-border);
		flex-shrink: 0;
	}

	.ingestion-stage.done .ingestion-stage-dot {
		background: #2f8a4d;
	}

	.ingestion-stage.active .ingestion-stage-dot {
		background: var(--color-primary);
	}

	.ingestion-action-error {
		font-size: 0.78rem;
		color: #d55b5b;
	}

	.ingestion-action-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		padding: 0.45rem 1rem;
		border-radius: 999px;
		border: none;
		font-size: 0.82rem;
		font-weight: 600;
		cursor: pointer;
		transition: opacity 0.15s;
	}

	.ingestion-action-btn:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}

	.ingestion-action-retry {
		background: var(--color-primary);
		color: var(--color-primary-foreground);
	}

	.ingestion-action-cancel {
		background: var(--color-secondary);
		border: 1px solid var(--color-border);
		color: var(--color-foreground);
	}
</style>
