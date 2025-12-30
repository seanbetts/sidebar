<script lang="ts">
  import { X } from 'lucide-svelte';
  import { ingestionViewerStore } from '$lib/stores/ingestion-viewer';

  $: active = $ingestionViewerStore.active;
  $: loading = $ingestionViewerStore.loading;
  $: error = $ingestionViewerStore.error;
  $: viewerKind = active?.recommended_viewer;
  $: viewerUrl =
    active && viewerKind
      ? `/api/ingestion/${active.file.id}/content?kind=${encodeURIComponent(viewerKind)}`
      : null;
  $: isPdf = viewerKind === 'viewer_pdf';
  $: filename = active?.file.filename_original ?? 'File viewer';
  $: displayName = stripExtension(filename);
  $: fileType = getFileType(filename, active?.file.mime_original);

  function handleClose() {
    ingestionViewerStore.clearActive();
  }

  function stripExtension(name: string): string {
    const index = name.lastIndexOf('.');
    if (index <= 0) return name;
    return name.slice(0, index);
  }

  function getFileType(name: string, mime?: string): string {
    if (mime) return mime;
    const index = name.lastIndexOf('.');
    if (index > 0 && index < name.length - 1) {
      return name.slice(index + 1).toUpperCase();
    }
    return 'FILE';
  }
</script>

<div class="file-viewer">
  <div class="file-viewer-header">
    <div class="file-viewer-meta">
        <div class="file-viewer-title-row">
          <div class="file-viewer-title">{displayName}</div>
          {#if active}
          <div class="file-viewer-divider"></div>
          <div class="file-viewer-type">{fileType}</div>
          {/if}
        </div>
    </div>
    <button class="viewer-close" onclick={handleClose} aria-label="Close file viewer">
      <X size={16} />
    </button>
  </div>

  <div class="file-viewer-body">
    {#if loading}
      <div class="viewer-placeholder">Loading file…</div>
    {:else if error}
      <div class="viewer-placeholder">{error}</div>
    {:else if !viewerUrl}
      <div class="viewer-placeholder">No preview available.</div>
    {:else if isPdf}
      <iframe class="file-viewer-frame" title="PDF preview" src={viewerUrl}></iframe>
    {:else}
      <img class="file-viewer-image" src={viewerUrl} alt={active?.file.filename_original ?? 'File'} />
    {/if}
  </div>
</div>

<style>
  .file-viewer {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
  }

  .file-viewer-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.85rem 1.2rem;
    border-bottom: 1px solid var(--color-border);
    gap: 1rem;
  }

  .file-viewer-meta {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
  }

  .file-viewer-title-row {
    display: flex;
    align-items: baseline;
    gap: 0.7rem;
    min-width: 0;
    min-height: 1.8rem; 
  }

  .file-viewer-title {
    font-size: 1rem;
    line-height: 1.6;
    font-weight: 600;
    color: var(--color-foreground);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .file-viewer-type {
    font-size: 0.7rem;
    line-height: 1.6;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--color-muted-foreground);
    flex-shrink: 0;
  }

  .file-viewer-divider {
    width: 2px;
    height: 1.8rem;
    background: var(--color-border);
    align-self: center;
    flex-shrink: 0;
  }

  .file-viewer-body {
    flex: 1;
    min-height: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 1rem;
    background: var(--color-background);
  }

  .viewer-close {
    border: none;
    background: transparent;
    color: var(--color-muted-foreground);
    cursor: pointer;
    padding: 0.25rem;
  }

  .viewer-close:hover {
    color: var(--color-foreground);
  }

  .viewer-placeholder {
    color: var(--color-muted-foreground);
    font-size: 0.9rem;
  }

  .file-viewer-frame {
    width: 100%;
    height: 100%;
    border: none;
    background: var(--color-background);
  }

  .file-viewer-image {
    max-width: 100%;
    max-height: 100%;
    border-radius: 0.5rem;
    object-fit: contain;
    box-shadow: 0 20px 40px rgba(0, 0, 0, 0.08);
  }
</style>
