<script lang="ts">
  import { Pause, Play, X } from 'lucide-svelte';
  import { ingestionAPI } from '$lib/services/api';
  import { ingestionStore } from '$lib/stores/ingestion';
  import { buildIngestionStatusMessage } from '$lib/utils/ingestionStatus';
  import type { IngestionListItem } from '$lib/types/ingestion';
  import { logError } from '$lib/utils/errorHandling';

  export let items: IngestionListItem[] = [];

  const stageOrder = ['uploading', 'queued', 'validating', 'converting', 'extracting', 'ai_md', 'thumb', 'finalizing', 'ready'];

  function getProgress(stage: string | null, progress: number | null | undefined): number {
    if (!stage) return 0;
    if (stage === 'uploading' && typeof progress === 'number') {
      return Math.round(progress);
    }
    const index = stageOrder.indexOf(stage);
    if (index < 0) return 0;
    return Math.round((index / (stageOrder.length - 1)) * 100);
  }


  async function handlePause(fileId: string) {
    try {
      await ingestionAPI.pause(fileId);
      const meta = await ingestionAPI.get(fileId);
      ingestionStore.upsertItem({
        file: meta.file,
        job: meta.job,
        recommended_viewer: meta.recommended_viewer
      });
    } catch (error) {
      logError('Failed to pause ingestion', error, { scope: 'IngestionQueue', fileId });
    }
  }

  async function handleResume(fileId: string) {
    try {
      await ingestionAPI.resume(fileId);
      const meta = await ingestionAPI.get(fileId);
      ingestionStore.upsertItem({
        file: meta.file,
        job: meta.job,
        recommended_viewer: meta.recommended_viewer
      });
    } catch (error) {
      logError('Failed to resume ingestion', error, { scope: 'IngestionQueue', fileId });
    }
  }

  async function handleCancel(fileId: string) {
    try {
      await ingestionAPI.cancel(fileId);
      const meta = await ingestionAPI.get(fileId);
      ingestionStore.upsertItem({
        file: meta.file,
        job: meta.job,
        recommended_viewer: meta.recommended_viewer
      });
    } catch (error) {
      logError('Failed to cancel ingestion', error, { scope: 'IngestionQueue', fileId });
    }
  }
</script>

<div class="ingestion-queue">
  <div class="ingestion-title">Processing uploads</div>
  {#each items as item (item.file.id)}
    <div class="ingestion-item">
      <div class="ingestion-header">
        <span class="filename">{item.file.filename_original}</span>
        <div class="status-row">
          <span class="status">{buildIngestionStatusMessage(item.job)}</span>
          <div class="actions">
            {#if item.job.status === 'processing'}
              <button class="action" onclick={() => handlePause(item.file.id)} aria-label="Pause">
                <Pause size={14} />
              </button>
            {:else if item.job.status === 'paused'}
              <button class="action" onclick={() => handleResume(item.file.id)} aria-label="Resume">
                <Play size={14} />
              </button>
            {/if}
            {#if item.job.status !== 'ready' && item.job.status !== 'uploading'}
              <button class="action" onclick={() => handleCancel(item.file.id)} aria-label="Cancel">
                <X size={14} />
              </button>
            {/if}
          </div>
        </div>
      </div>
      <div class="progress">
        <div class="progress-bar" style={`width: ${getProgress(item.job.stage || item.job.status, item.job.progress)}%`}></div>
      </div>
    </div>
  {/each}
</div>

<style>
  .ingestion-queue {
    padding: 0.5rem 0.75rem 0.25rem;
    border-bottom: 1px solid var(--color-sidebar-border);
  }

  .ingestion-title {
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--color-muted-foreground);
    font-weight: 600;
    margin-bottom: 0.5rem;
  }

  .ingestion-item {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    padding: 0.35rem 0;
  }

  .ingestion-header {
    display: flex;
    justify-content: space-between;
    gap: 0.5rem;
    align-items: center;
  }

  .filename {
    font-size: 0.85rem;
    color: var(--color-foreground);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .status {
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--color-muted-foreground);
  }

  .status-row {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
  }

  .actions {
    display: inline-flex;
    align-items: center;
    gap: 0.2rem;
  }

  .action {
    border: none;
    background: transparent;
    padding: 0;
    cursor: pointer;
    color: var(--color-muted-foreground);
  }

  .action:hover {
    color: var(--color-foreground);
  }

  .progress {
    height: 4px;
    background: var(--color-border);
    border-radius: 999px;
    overflow: hidden;
  }

  .progress-bar {
    height: 100%;
    background: var(--color-sidebar-primary);
    transition: width 0.2s ease;
  }
</style>
