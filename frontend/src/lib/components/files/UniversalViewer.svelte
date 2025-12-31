<script lang="ts">
  import { onMount } from 'svelte';
  import { browser } from '$app/environment';
  import {
    GalleryHorizontal,
    GalleryVertical,
    ChevronLeft,
    ChevronRight,
    Copy,
    Download,
    Check,
    FileSpreadsheet,
    FileText,
    Image,
    AlertTriangle,
    Menu,
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
  import * as Popover from '$lib/components/ui/popover/index.js';
  import { ingestionAPI } from '$lib/services/api';
  import { dispatchCacheEvent } from '$lib/utils/cacheEvents';
  import { ingestionStore } from '$lib/stores/ingestion';
  import { buildIngestionStatusMessage } from '$lib/utils/ingestionStatus';
  import TextInputDialog from '$lib/components/left-sidebar/dialogs/TextInputDialog.svelte';
  import SpreadsheetViewer from '$lib/components/files/SpreadsheetViewer.svelte';

  $: active = $ingestionViewerStore.active;
  $: loading = $ingestionViewerStore.loading;
  $: error = $ingestionViewerStore.error;
  $: viewerKind = active?.recommended_viewer;
  $: viewerUrl =
    active && viewerKind
      ? `/api/ingestion/${active.file.id}/content?kind=${encodeURIComponent(viewerKind)}`
      : null;
  $: isPdf = viewerKind === 'viewer_pdf';
  $: isText = viewerKind === 'text_original';
  $: isSpreadsheet = viewerKind === 'viewer_json';
  $: isImage = active?.file.category === 'images';
  $: filename = active?.file.filename_original ?? 'File viewer';
  $: displayName = stripExtension(filename);
  $: fileType = getFileType(filename, active?.file.mime_original);
  $: jobStatus = active?.job?.status ?? null;
  $: jobStage = active?.job?.stage ?? null;
  $: isFailed = jobStatus === 'failed';
  $: isInProgress = Boolean(jobStatus && jobStatus !== 'ready' && jobStatus !== 'failed');
  $: statusMessage = buildIngestionStatusMessage(active?.job);
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
  let isRenameOpen = false;
  let renameValue = '';
  let isRenaming = false;
  let textContent = '';
  let textError = '';
  let isTextLoading = false;
  let lastTextUrl: string | null = null;
  let spreadsheetActions: { copy: () => void; download: () => void } | null = null;

  $: if (active) {
    const item = $ingestionStore.items.find(entry => entry.file.id === active.file.id);
    if (item && item.job) {
      ingestionViewerStore.updateActiveJob(active.file.id, item.job);
    }
  }

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
    if (isSpreadsheet && spreadsheetActions) {
      spreadsheetActions.download();
      return;
    }
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
    if (isSpreadsheet && spreadsheetActions) {
      spreadsheetActions.copy();
      isCopied = true;
      if (copyTimeout) clearTimeout(copyTimeout);
      copyTimeout = setTimeout(() => {
        isCopied = false;
      }, 1500);
      return;
    }
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

  function openRenameDialog() {
    if (!active) return;
    renameValue = stripExtension(active.file.filename_original);
    isRenameOpen = true;
  }

  async function confirmRename() {
    if (!active) return;
    const original = active.file.filename_original;
    const extensionMatch = original.match(/\.[^/.]+$/);
    const extension = extensionMatch ? extensionMatch[0] : '';
    const trimmed = renameValue.trim();
    if (!trimmed) return;
    const filename = extension && !trimmed.endsWith(extension)
      ? `${trimmed}${extension}`
      : trimmed;
    if (filename === original) {
      isRenameOpen = false;
      return;
    }
    isRenaming = true;
    try {
      await ingestionAPI.rename(active.file.id, filename);
      ingestionViewerStore.updateFilename(active.file.id, filename);
      ingestionStore.updateFilename(active.file.id, filename);
      isRenameOpen = false;
    } catch (error) {
      console.error('Failed to rename file:', error);
    } finally {
      isRenaming = false;
    }
  }

  function stripExtension(name: string): string {
    const index = name.lastIndexOf('.');
    if (index <= 0) return name;
    return name.slice(0, index);
  }

  function getFileType(name: string, mime?: string): string {
    if (mime) {
      const normalized = mime.split(';')[0].trim().toLowerCase();
      const pretty = {
        'application/pdf': 'PDF',
        'application/vnd.ms-excel': 'XLS',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'DOCX',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'XLSX',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'PPTX',
        'text/csv': 'CSV',
        'application/csv': 'CSV',
        'text/tab-separated-values': 'TSV',
        'text/tsv': 'TSV'
      } as Record<string, string>;
      if (normalized.startsWith('image/')) {
        const imageSubtype = normalized.split('/')[1] ?? 'image';
        return imageSubtype.toUpperCase();
      }
      if (normalized === 'application/octet-stream') {
        const index = name.lastIndexOf('.');
        if (index > 0 && index < name.length - 1) {
          return name.slice(index + 1).toUpperCase();
        }
      }
      return pretty[normalized] ?? mime;
    }
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
    textContent = '';
    textError = '';
    lastTextUrl = null;
    spreadsheetActions = null;
  }

  $: if (browser && isText && viewerUrl && viewerUrl !== lastTextUrl) {
    lastTextUrl = viewerUrl;
    textContent = '';
    textError = '';
    isTextLoading = true;
    fetch(viewerUrl, { credentials: 'include' })
      .then(async (response) => {
        if (!response.ok) {
          throw new Error('Failed to load text');
        }
        return response.text();
      })
      .then((text) => {
        textContent = text;
      })
      .catch((error) => {
        console.error('Failed to load text content:', error);
        textError = 'Failed to load text content.';
      })
      .finally(() => {
        isTextLoading = false;
      });
  }
</script>

<div class="file-viewer">
  <div class="file-viewer-header" class:pdf-header={isPdf}>
    <div class="file-viewer-meta">
      <div class="file-viewer-title-row">
        <span class="file-viewer-icon">
          {#if isImage}
            <Image size={18} />
          {:else if isSpreadsheet}
            <FileSpreadsheet size={18} />
          {:else}
            <FileText size={18} />
          {/if}
        </span>
        <div class="file-viewer-title">{displayName}</div>
        {#if active}
          <div class="file-viewer-divider"></div>
          <div class="file-viewer-type">{fileType}</div>
        {/if}
      </div>
    </div>
    <div class="file-viewer-controls">
      {#if isPdf}
        <div class="pdf-controls-inline">
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
            onclick={() => setFitMode('height')}
            data-active={fitMode === 'height'}
            aria-label="Fit to height"
          >
            <GalleryVertical size={16} />
          </Button>
          <Button
            size="icon"
            variant="ghost"
            class="viewer-control"
            onclick={() => setFitMode('width')}
            data-active={fitMode === 'width'}
            aria-label="Fit to width"
          >
            <GalleryHorizontal size={16} />
          </Button>
        </div>
      {/if}
      <div class="viewer-standard-actions">
        {#if isPdf}
          <div class="viewer-divider"></div>
        {/if}
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
          disabled={!active}
          aria-label="Rename file"
          title="Rename file"
          onclick={openRenameDialog}
        >
          <Pencil size={16} />
        </Button>
        <Button
          size="icon"
          variant="ghost"
          class="viewer-control"
          onclick={handleDownload}
          aria-label={isSpreadsheet ? 'Download CSV' : 'Download file'}
          title={isSpreadsheet ? 'Download CSV' : 'Download file'}
        >
          <Download size={16} />
        </Button>
        <Button
          size="icon"
          variant="ghost"
          class="viewer-control"
          onclick={handleCopyMarkdown}
          disabled={!hasMarkdown && !isSpreadsheet}
          aria-label={isSpreadsheet ? 'Copy CSV' : 'Copy markdown'}
          title={isSpreadsheet ? 'Copy CSV' : hasMarkdown ? 'Copy markdown' : 'Markdown not available'}
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
      <div class="viewer-standard-compact">
        <Popover.Root>
          <Popover.Trigger>
            {#snippet child({ props })}
              <Button size="icon" variant="ghost" {...props} aria-label="More actions" title="More actions">
                <Menu size={16} />
              </Button>
            {/snippet}
          </Popover.Trigger>
          <Popover.Content class="viewer-actions-menu" align="end" sideOffset={8}>
            {#if isPdf}
              <div class="viewer-menu-label">Page {currentPage} / {pageCount || 1}</div>
              <div class="viewer-menu-row">
                <button class="viewer-menu-item" onclick={prevPage} disabled={!canPrev}>
                  <ChevronLeft size={16} />
                  <span>Prev page</span>
                </button>
                <button class="viewer-menu-item" onclick={nextPage} disabled={!canNext}>
                  <ChevronRight size={16} />
                  <span>Next page</span>
                </button>
              </div>
              <div class="viewer-menu-label">Zoom {Math.round((isPdf ? normalizedScale : scale) * 100)}%</div>
              <div class="viewer-menu-row">
                <button class="viewer-menu-item" onclick={zoomOut}>
                  <Minus size={16} />
                  <span>Zoom out</span>
                </button>
                <button class="viewer-menu-item" onclick={zoomIn}>
                  <Plus size={16} />
                  <span>Zoom in</span>
                </button>
              </div>
              <div class="viewer-menu-row">
                <button class="viewer-menu-item" onclick={() => setFitMode('height')}>
                  <GalleryVertical size={16} />
                  <span>Fit height</span>
                </button>
                <button class="viewer-menu-item" onclick={() => setFitMode('width')}>
                  <GalleryHorizontal size={16} />
                  <span>Fit width</span>
                </button>
              </div>
              <div class="viewer-menu-divider"></div>
            {/if}
            <button class="viewer-menu-item" onclick={handlePinToggle} disabled={!active}>
              {#if active?.file.pinned}
                <PinOff size={16} />
                <span>Unpin</span>
              {:else}
                <Pin size={16} />
                <span>Pin</span>
              {/if}
            </button>
            <button class="viewer-menu-item" onclick={openRenameDialog} disabled={!active}>
              <Pencil size={16} />
              <span>Rename</span>
            </button>
            <button class="viewer-menu-item" onclick={handleDownload}>
              <Download size={16} />
              <span>{isSpreadsheet ? 'Download CSV' : 'Download'}</span>
            </button>
            <button class="viewer-menu-item" onclick={handleCopyMarkdown} disabled={!hasMarkdown && !isSpreadsheet}>
              {#if isCopied}
                <Check size={16} />
                <span>Copied</span>
              {:else}
                <Copy size={16} />
                <span>{isSpreadsheet ? 'Copy CSV' : 'Copy'}</span>
              {/if}
            </button>
            <button class="viewer-menu-item" onclick={handleDelete} disabled={!active}>
              <Trash2 size={16} />
              <span>Delete</span>
            </button>
            <button class="viewer-menu-item" onclick={handleClose}>
              <X size={16} />
              <span>Close</span>
            </button>
          </Popover.Content>
        </Popover.Root>
      </div>
    </div>
  </div>

  <div class="file-viewer-body">
    {#if loading}
      <div class="viewer-placeholder">Loading file…</div>
    {:else if error}
      <div class="viewer-placeholder">{error}</div>
    {:else if !viewerUrl}
      <div class="viewer-placeholder">
        {#if isFailed}
          <div class="viewer-placeholder-stack">
            <AlertTriangle size={20} class="viewer-placeholder-alert" />
            <span>{statusMessage}</span>
          </div>
        {:else if isInProgress}
          <div class="viewer-placeholder-stack">
            <span class="viewer-spinner" aria-hidden="true"></span>
            <span>{statusMessage}</span>
          </div>
        {:else}
          No preview available.
        {/if}
      </div>
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
    {:else if isSpreadsheet}
      <SpreadsheetViewer
        src={viewerUrl}
        filename={displayName}
        registerActions={(actions) => (spreadsheetActions = actions)}
      />
    {:else if isText}
      {#if isTextLoading}
        <div class="viewer-placeholder">Loading text…</div>
      {:else if textError}
        <div class="viewer-placeholder">{textError}</div>
      {:else}
        <pre class="file-viewer-text">{textContent}</pre>
      {/if}
    {:else}
      <img class="file-viewer-image" src={viewerUrl} alt={active?.file.filename_original ?? 'File'} />
    {/if}
  </div>
</div>

<TextInputDialog
  bind:open={isRenameOpen}
  title="Rename file"
  description="Update the file name."
  placeholder="File name"
  bind:value={renameValue}
  confirmLabel="Rename"
  cancelLabel="Cancel"
  busyLabel="Renaming..."
  isBusy={isRenaming}
  onConfirm={confirmRename}
  onCancel={() => (isRenameOpen = false)}
/>

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
    container-type: inline-size;
  }

  .file-viewer-meta {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
  }

  .file-viewer-title-row {
    display: flex;
    align-items: center;
    gap: 0.7rem;
    min-width: 0;
    min-height: 1.8rem; 
  }

  .file-viewer-icon {
    display: inline-flex;
    align-items: center;
    color: var(--color-foreground);
    flex-shrink: 0;
  }

  .file-viewer-title {
    font-size: 1.125rem;
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

  .viewer-standard-actions {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
  }

  .pdf-controls-inline {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
  }

  .viewer-standard-compact {
    display: none;
  }

  :global(.viewer-actions-menu) {
    width: max-content !important;
    min-width: 0 !important;
    padding: 0.25rem 0;
  }

  .viewer-menu-item {
    display: flex;
    align-items: center;
    gap: 0.6rem;
    width: 100%;
    border: none;
    background: none;
    cursor: pointer;
    padding: 0.45rem 0.75rem;
    text-align: left;
    font-size: 0.8rem;
    color: var(--color-popover-foreground);
  }

  .viewer-menu-item:hover {
    background-color: var(--color-accent);
  }

  .viewer-menu-item:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .viewer-menu-label {
    padding: 0.35rem 0.75rem 0.1rem;
    font-size: 0.65rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--color-muted-foreground);
  }

  .viewer-menu-row {
    display: grid;
    gap: 0.15rem;
    padding: 0 0.15rem 0.2rem;
  }

  .viewer-menu-divider {
    height: 1px;
    background: var(--color-border);
    margin: 0.35rem 0.35rem 0.2rem;
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

  .viewer-placeholder-stack {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.5rem;
    text-align: center;
  }

  .viewer-spinner {
    width: 20px;
    height: 20px;
    border-radius: 999px;
    border: 2px solid var(--color-border);
    border-top-color: var(--color-sidebar-primary);
    animation: viewer-spin 0.8s linear infinite;
  }

  @keyframes viewer-spin {
    to {
      transform: rotate(360deg);
    }
  }

  .viewer-placeholder-alert {
    color: var(--color-destructive);
  }


  .file-viewer-image {
    max-width: 100%;
    max-height: 100%;
    border-radius: 0.5rem;
    object-fit: contain;
    box-shadow: 0 20px 40px rgba(0, 0, 0, 0.08);
  }

  .file-viewer-text {
    width: min(960px, 100%);
    max-height: 100%;
    overflow: auto;
    padding: 1rem;
    border-radius: 0.5rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    font-family: var(--font-mono);
    font-size: 0.85rem;
    line-height: 1.6;
    white-space: pre-wrap;
  }

  @container (max-width: 700px) {
    .viewer-standard-actions {
      display: none;
    }

    .viewer-standard-compact {
      display: inline-flex;
      align-items: center;
    }

    .pdf-controls-inline {
      display: none;
    }
  }

  @container (max-width: 860px) {
    .pdf-header .viewer-standard-actions {
      display: none;
    }

    .pdf-header .viewer-standard-compact {
      display: inline-flex;
      align-items: center;
    }
  }
</style>
