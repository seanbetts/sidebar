<script lang="ts">
  import type { IngestionListItem } from '$lib/types/ingestion';

  export let items: IngestionListItem[] = [];

  const stageOrder = ['queued', 'validating', 'converting', 'extracting', 'ai_md', 'thumb', 'finalizing', 'ready'];

  function getProgress(stage: string | null): number {
    if (!stage) return 0;
    const index = stageOrder.indexOf(stage);
    if (index < 0) return 0;
    return Math.round((index / (stageOrder.length - 1)) * 100);
  }
</script>

<div class="ingestion-queue">
  <div class="ingestion-title">Processing uploads</div>
  {#each items as item (item.file.id)}
    <div class="ingestion-item">
      <div class="ingestion-header">
        <span class="filename">{item.file.filename_original}</span>
        <span class="status">{item.job.stage || item.job.status || 'queued'}</span>
      </div>
      <div class="progress">
        <div class="progress-bar" style={`width: ${getProgress(item.job.stage || item.job.status)}%`}></div>
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
