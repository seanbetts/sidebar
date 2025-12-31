<script lang="ts">
  import { onMount } from 'svelte';
  import { browser } from '$app/environment';
  import {
    ArrowLeftRight,
    ArrowUpDown,
    ChevronLeft,
    ChevronRight,
    Download,
    Minus,
    Plus,
    Printer,
    X
  } from 'lucide-svelte';
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
  $: canPrev = currentPage > 1;
  $: canNext = pageCount > 0 && currentPage < pageCount;

  let currentPage = 1;
  let pageCount = 0;
  let scale = 1;
  let fitMode: 'auto' | 'width' | 'height' = 'height';
  let activeId: string | null = null;
  let effectiveScale = 1;
  let normalizedScale = 1;
  let PdfViewerComponent: typeof import('$lib/components/files/PdfViewer.svelte').default | null = null;

  onMount(async () => {
    if (!browser) return;
    const module = await import('$lib/components/files/PdfViewer.svelte');
    PdfViewerComponent = module.default;
  });

  function handleClose() {
    ingestionViewerStore.clearActive();
  }

  function zoomIn() {
    scale = Math.min(3, scale + 0.1);
  }

  function zoomOut() {
    scale = Math.max(0.5, scale - 0.1);
  }

  function prevPage() {
    if (currentPage > 1) currentPage -= 1;
  }

  function nextPage() {
    if (pageCount && currentPage < pageCount) currentPage += 1;
  }

  function setFitMode(mode: 'auto' | 'width' | 'height') {
    fitMode = mode;
    scale = 1;
  }

  async function handleDownload() {
    if (!viewerUrl || !browser) return;
    const response = await fetch(viewerUrl, { credentials: 'include' });
    if (!response.ok) return;
    const blob = await response.blob();
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    link.click();
    URL.revokeObjectURL(url);
  }

  async function handlePrint() {
    if (!viewerUrl || !browser) return;
    const response = await fetch(viewerUrl, { credentials: 'include' });
    if (!response.ok) return;
    const blob = await response.blob();
    const url = URL.createObjectURL(blob);
    const frame = document.createElement('iframe');
    frame.style.position = 'fixed';
    frame.style.right = '0';
    frame.style.bottom = '0';
    frame.style.width = '0';
    frame.style.height = '0';
    frame.style.border = '0';
    frame.src = url;
    frame.onload = () => {
      frame.contentWindow?.focus();
      frame.contentWindow?.print();
      setTimeout(() => {
        URL.revokeObjectURL(url);
        frame.remove();
      }, 500);
    };
    document.body.appendChild(frame);
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

  $: if (active?.file.id && activeId !== active.file.id) {
    activeId = active.file.id;
    currentPage = 1;
    pageCount = 0;
    scale = 1;
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
    <div class="file-viewer-controls">
      {#if isPdf}
        <button class="viewer-control" on:click={prevPage} disabled={!canPrev} aria-label="Previous page">
          <ChevronLeft size={16} />
        </button>
        <span class="viewer-page">{currentPage} / {pageCount || 1}</span>
        <button class="viewer-control" on:click={nextPage} disabled={!canNext} aria-label="Next page">
          <ChevronRight size={16} />
        </button>
        <div class="viewer-divider"></div>
        <button class="viewer-control" on:click={zoomOut} aria-label="Zoom out">
          <Minus size={16} />
        </button>
        <span class="viewer-scale">{Math.round((isPdf ? normalizedScale : scale) * 100)}%</span>
        <button class="viewer-control" on:click={zoomIn} aria-label="Zoom in">
          <Plus size={16} />
        </button>
        <div class="viewer-divider"></div>
        <button
          class="viewer-control"
          on:click={() => setFitMode('width')}
          data-active={fitMode === 'width'}
          aria-label="Fit to width"
        >
          <ArrowLeftRight size={16} />
        </button>
        <button
          class="viewer-control"
          on:click={() => setFitMode('height')}
          data-active={fitMode === 'height'}
          aria-label="Fit to height"
        >
          <ArrowUpDown size={16} />
        </button>
        <div class="viewer-divider"></div>
        <button class="viewer-control" on:click={handleDownload} aria-label="Download file">
          <Download size={16} />
        </button>
        <button class="viewer-control" on:click={handlePrint} aria-label="Print file">
          <Printer size={16} />
        </button>
      {/if}
      <button class="viewer-close" on:click={handleClose} aria-label="Close file viewer">
      <X size={16} />
    </button>
    </div>
  </div>

  <div class="file-viewer-body">
    {#if loading}
      <div class="viewer-placeholder">Loading file…</div>
    {:else if error}
      <div class="viewer-placeholder">{error}</div>
    {:else if !viewerUrl}
      <div class="viewer-placeholder">No preview available.</div>
    {:else if isPdf}
      {#if PdfViewerComponent}
        <svelte:component
          this={PdfViewerComponent}
          src={viewerUrl}
          fitMode={fitMode}
          bind:effectiveScale
          bind:normalizedScale
          bind:currentPage
          bind:pageCount
          bind:scale
        />
      {:else}
        <div class="viewer-placeholder">Loading PDF…</div>
      {/if}
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
    font-size: 1.25rem;
    line-height: 1.4;
    font-weight: 600;
    color: var(--color-foreground);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .file-viewer-type {
    font-size: 0.7rem;
    line-height: 1.4;
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

  .file-viewer-controls {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
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

  .viewer-control {
    border: none;
    background: transparent;
    color: var(--color-muted-foreground);
    cursor: pointer;
    padding: 0.25rem;
  }

  .viewer-control[data-active='true'] {
    color: var(--color-foreground);
  }

  .viewer-control:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .viewer-control:hover:not(:disabled) {
    color: var(--color-foreground);
  }

  .viewer-page,
  .viewer-scale {
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--color-muted-foreground);
    min-width: 48px;
    text-align: center;
  }

  .viewer-divider {
    width: 1px;
    height: 1.25rem;
    background: var(--color-border);
  }

  .viewer-placeholder {
    color: var(--color-muted-foreground);
    font-size: 0.9rem;
  }

  .file-viewer-image {
    max-width: 100%;
    max-height: 100%;
    border-radius: 0.5rem;
    object-fit: contain;
    box-shadow: 0 20px 40px rgba(0, 0, 0, 0.08);
  }
</style>
