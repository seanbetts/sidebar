<script lang="ts">
  import { onMount } from 'svelte';
  import { browser } from '$app/environment';
  import {
    ArrowLeftRight,
    ArrowUpDown,
    ChevronLeft,
    ChevronRight,
    Copy,
    Download,
    FolderInput,
    Check,
    Minus,
    Pencil,
    Pin,
    PinOff,
    Plus,
    Trash2,
    X
  } from 'lucide-svelte';
  import { ingestionViewerStore } from '$lib/stores/ingestion-viewer';
  import { Button } from '$lib/components/ui/button';
  import { ingestionAPI } from '$lib/services/api';
  import { dispatchCacheEvent } from '$lib/utils/cacheEvents';
  import { ingestionStore } from '$lib/stores/ingestion';

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
  $: hasMarkdown = Boolean(active?.derivatives?.some(item => item.kind === 'ai_md'));

  let currentPage = 1;
  let pageCount = 0;
  let scale = 1;
  let fitMode: 'auto' | 'width' | 'height' = 'height';
  let activeId: string | null = null;
  let effectiveScale = 1;
  let normalizedScale = 1;
  let PdfViewerComponent: typeof import('$lib/components/files/PdfViewer.svelte').default | null = null;
  let isCopied = false;
  let copyTimeout: ReturnType<typeof setTimeout> | null = null;

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

  async function handleCopyMarkdown() {
    if (!active || !hasMarkdown) return;
    try {
      const response = await ingestionAPI.getContent(active.file.id, 'ai_md');
      let text = await response.text();
      if (text.startsWith('---')) {
        const match = text.match(/^---\s*\n[\s\S]*?\n---\s*\n?/);
        if (match) {
          text = text.slice(match[0].length);
        }
      }
      if (browser && navigator.clipboard) {
        await navigator.clipboard.writeText(text);
      }
      isCopied = true;
      if (copyTimeout) clearTimeout(copyTimeout);
      copyTimeout = setTimeout(() => {
        isCopied = false;
      }, 1500);
    } catch (error) {
      console.error('Failed to copy markdown:', error);
    }
  }

  async function handleDelete() {
    if (!active) return;
    if (!browser || !confirm('Delete this file?')) return;
    try {
      await ingestionAPI.delete(active.file.id);
      dispatchCacheEvent('file.deleted');
      ingestionViewerStore.clearActive();
    } catch (error) {
      console.error('Failed to delete file:', error);
    }
  }

  async function handlePinToggle() {
    if (!active) return;
    try {
      const nextPinned = !active.file.pinned;
      await ingestionAPI.setPinned(active.file.id, nextPinned);
      ingestionViewerStore.updatePinned(active.file.id, nextPinned);
      ingestionStore.updatePinned(active.file.id, nextPinned);
    } catch (error) {
      console.error('Failed to update pin:', error);
    }
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
        <Button
          size="icon"
          variant="ghost"
          class="viewer-control"
          onclick={prevPage}
          disabled={!canPrev}
          aria-label="Previous page"
        >
          <ChevronLeft size={16} />
        </Button>
        <span class="viewer-page">{currentPage} / {pageCount || 1}</span>
        <Button
          size="icon"
          variant="ghost"
          class="viewer-control"
          onclick={nextPage}
          disabled={!canNext}
          aria-label="Next page"
        >
          <ChevronRight size={16} />
        </Button>
        <div class="viewer-divider"></div>
        <Button size="icon" variant="ghost" class="viewer-control" onclick={zoomOut} aria-label="Zoom out">
          <Minus size={16} />
        </Button>
        <span class="viewer-scale">{Math.round((isPdf ? normalizedScale : scale) * 100)}%</span>
        <Button size="icon" variant="ghost" class="viewer-control" onclick={zoomIn} aria-label="Zoom in">
          <Plus size={16} />
        </Button>
        <div class="viewer-divider"></div>
        <Button
          size="icon"
          variant="ghost"
          class="viewer-control"
          onclick={() => setFitMode('width')}
          data-active={fitMode === 'width'}
          aria-label="Fit to width"
        >
          <ArrowLeftRight size={16} />
        </Button>
        <Button
          size="icon"
          variant="ghost"
          class="viewer-control"
          onclick={() => setFitMode('height')}
          data-active={fitMode === 'height'}
          aria-label="Fit to height"
        >
          <ArrowUpDown size={16} />
        </Button>
      {/if}
      <div class="viewer-divider"></div>
      <Button
        size="icon"
        variant="ghost"
        class="viewer-control"
        onclick={handlePinToggle}
        disabled={!active}
        aria-label="Pin file"
        title="Pin file"
      >
        {#if active?.file.pinned}
          <PinOff size={16} />
        {:else}
          <Pin size={16} />
        {/if}
      </Button>
      <Button
        size="icon"
        variant="ghost"
        class="viewer-control"
        disabled
        aria-label="Rename file"
        title="Rename file (coming soon)"
      >
        <Pencil size={16} />
      </Button>
      <Button
        size="icon"
        variant="ghost"
        class="viewer-control"
        disabled
        aria-label="Move file"
        title="Move file (coming soon)"
      >
        <FolderInput size={16} />
      </Button>
      <Button
        size="icon"
        variant="ghost"
        class="viewer-control"
        onclick={handleDownload}
        aria-label="Download file"
        title="Download file"
      >
        <Download size={16} />
      </Button>
        <Button
          size="icon"
          variant="ghost"
          class="viewer-control"
          onclick={handleCopyMarkdown}
          disabled={!hasMarkdown}
          aria-label="Copy markdown"
          title={hasMarkdown ? 'Copy markdown' : 'Markdown not available'}
        >
          {#if isCopied}
            <Check size={16} />
          {:else}
            <Copy size={16} />
          {/if}
        </Button>
        <Button
          size="icon"
          variant="ghost"
          class="viewer-control"
          onclick={handleDelete}
          disabled={!active}
          aria-label="Delete file"
          title="Delete file"
        >
          <Trash2 size={16} />
        </Button>
      <Button size="icon" variant="ghost" class="viewer-close" onclick={handleClose} aria-label="Close file viewer">
        <X size={16} />
      </Button>
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
    padding: 0.63rem 1.2rem;
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

  .viewer-control[data-active='true'] {
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
