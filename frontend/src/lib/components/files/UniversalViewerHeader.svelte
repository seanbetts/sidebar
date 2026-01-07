<script lang="ts">
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
    FilePenLine,
    Image,
    FileMusic,
    FileVideoCamera,
    Menu,
    Minus,
    Pencil,
    Pin,
    PinOff,
    Plus,
    Trash2,
    X
  } from 'lucide-svelte';
  import { Button } from '$lib/components/ui/button';
  import * as Popover from '$lib/components/ui/popover/index.js';
  import { Tooltip, TooltipContent, TooltipTrigger } from '$lib/components/ui/tooltip';
  import { TOOLTIP_COPY } from '$lib/constants/tooltips';
  import { canShowTooltips } from '$lib/utils/tooltip';
  import { onMount } from 'svelte';

  export let isImage = false;
  export let isAudio = false;
  export let isVideo = false;
  export let isSpreadsheet = false;
  export let isPdf = false;
  export let displayName = '';
  export let fileType = '';
  export let hasActive = false;
  export let isPinned = false;
  export let showMarkdownToggle = false;
  export let viewMode: 'content' | 'markdown' = 'content';
  export let viewerUrl: string | null = null;
  export let hasMarkdown = false;
  export let isCopied = false;
  export let currentPage = 1;
  export let pageCount = 0;
  export let canPrev = false;
  export let canNext = false;
  export let scale = 1;
  export let normalizedScale = 1;
  export let fitMode: 'auto' | 'width' | 'height' = 'height';

  export let onPrevPage: () => void;
  export let onNextPage: () => void;
  export let onZoomOut: () => void;
  export let onZoomIn: () => void;
  export let onSetFitMode: (mode: 'auto' | 'width' | 'height') => void;
  export let onPinToggle: () => void;
  export let onRename: () => void;
  export let onDownload: () => void;
  export let onCopyMarkdown: () => void;
  export let onDelete: () => void;
  export let onClose: () => void;

  let tooltipsEnabled = false;
  $: downloadLabel = isSpreadsheet ? TOOLTIP_COPY.downloadCsv : TOOLTIP_COPY.downloadFile;
  $: copyLabel = isSpreadsheet ? TOOLTIP_COPY.copyCsv : TOOLTIP_COPY.copyMarkdown;
  $: copyTooltip = isCopied ? TOOLTIP_COPY.copy.success : copyLabel;
  $: pinTooltip = isPinned ? TOOLTIP_COPY.pin.on : TOOLTIP_COPY.pin.off;

  onMount(() => {
    tooltipsEnabled = canShowTooltips();
  });
</script>

<div class="file-viewer-header" class:pdf-header={isPdf}>
  <div class="file-viewer-meta">
    <div class="file-viewer-title-row">
      <span class="file-viewer-icon">
        {#if isImage}
          <Image size={18} />
        {:else if isAudio}
          <FileMusic size={18} />
        {:else if isVideo}
          <FileVideoCamera size={18} />
        {:else if isSpreadsheet}
          <FileSpreadsheet size={18} />
        {:else}
          <FileText size={18} />
        {/if}
      </span>
      <div class="file-viewer-title">{displayName}</div>
      {#if hasActive && fileType}
        <div class="file-viewer-divider"></div>
        <div class="file-viewer-type">{fileType}</div>
      {/if}
    </div>
  </div>
  {#if showMarkdownToggle}
    <div class="viewer-toggle-center">
      <div class="viewer-toggle viewer-toggle--compact">
        <Tooltip disabled={!tooltipsEnabled}>
          <TooltipTrigger>
            {#snippet child({ props })}
              <button
                class="viewer-toggle-button"
                class:active={viewMode === 'content'}
                {...props}
                onclick={(event) => {
                  props.onclick?.(event);
                  viewMode = 'content';
                }}
                aria-label="View file"
              >
                {#if isImage}
                  <Image size={16} />
                {:else if isSpreadsheet}
                  <FileSpreadsheet size={16} />
                {:else}
                  <FileText size={16} />
                {/if}
              </button>
            {/snippet}
          </TooltipTrigger>
          <TooltipContent side="bottom">{TOOLTIP_COPY.viewFile}</TooltipContent>
        </Tooltip>
        <Tooltip disabled={!tooltipsEnabled}>
          <TooltipTrigger>
            {#snippet child({ props })}
              <button
                class="viewer-toggle-button"
                class:active={viewMode === 'markdown'}
                {...props}
                onclick={(event) => {
                  props.onclick?.(event);
                  viewMode = 'markdown';
                }}
                aria-label="View markdown"
              >
                <FilePenLine size={16} />
              </button>
            {/snippet}
          </TooltipTrigger>
          <TooltipContent side="bottom">{TOOLTIP_COPY.viewMarkdown}</TooltipContent>
        </Tooltip>
      </div>
    </div>
  {/if}
  <div class="file-viewer-controls">
    {#if showMarkdownToggle}
      <div class="viewer-toggle-compact">
        <div class="viewer-toggle viewer-toggle--compact">
          <Tooltip disabled={!tooltipsEnabled}>
            <TooltipTrigger>
              {#snippet child({ props })}
                <button
                  class="viewer-toggle-button"
                  class:active={viewMode === 'content'}
                  {...props}
                  onclick={(event) => {
                    props.onclick?.(event);
                    viewMode = 'content';
                  }}
                  aria-label="View file"
                >
                  {#if isImage}
                    <Image size={16} />
                  {:else if isSpreadsheet}
                    <FileSpreadsheet size={16} />
                  {:else}
                    <FileText size={16} />
                  {/if}
                </button>
              {/snippet}
            </TooltipTrigger>
            <TooltipContent side="bottom">{TOOLTIP_COPY.viewFile}</TooltipContent>
          </Tooltip>
          <Tooltip disabled={!tooltipsEnabled}>
            <TooltipTrigger>
              {#snippet child({ props })}
                <button
                  class="viewer-toggle-button"
                  class:active={viewMode === 'markdown'}
                  {...props}
                  onclick={(event) => {
                    props.onclick?.(event);
                    viewMode = 'markdown';
                  }}
                  aria-label="View markdown"
                >
                  <FilePenLine size={16} />
                </button>
              {/snippet}
            </TooltipTrigger>
            <TooltipContent side="bottom">{TOOLTIP_COPY.viewMarkdown}</TooltipContent>
          </Tooltip>
        </div>
      </div>
    {/if}
    {#if isPdf}
      <div class="pdf-controls-inline" class:hidden={viewMode === 'markdown'}>
        <Tooltip disabled={!tooltipsEnabled}>
          <TooltipTrigger>
            {#snippet child({ props })}
              <Button
                size="icon"
                variant="ghost"
                class="viewer-control"
                {...props}
                onclick={(event) => {
                  props.onclick?.(event);
                  onPrevPage();
                }}
                disabled={!canPrev}
                aria-label="Previous page"
              >
                <ChevronLeft size={16} />
              </Button>
            {/snippet}
          </TooltipTrigger>
          <TooltipContent side="bottom">{TOOLTIP_COPY.prevPage}</TooltipContent>
        </Tooltip>
        <span class="viewer-page">{currentPage} / {pageCount || 1}</span>
        <Tooltip disabled={!tooltipsEnabled}>
          <TooltipTrigger>
            {#snippet child({ props })}
              <Button
                size="icon"
                variant="ghost"
                class="viewer-control"
                {...props}
                onclick={(event) => {
                  props.onclick?.(event);
                  onNextPage();
                }}
                disabled={!canNext}
                aria-label="Next page"
              >
                <ChevronRight size={16} />
              </Button>
            {/snippet}
          </TooltipTrigger>
          <TooltipContent side="bottom">{TOOLTIP_COPY.nextPage}</TooltipContent>
        </Tooltip>
        <div class="viewer-divider"></div>
        <Tooltip disabled={!tooltipsEnabled}>
          <TooltipTrigger>
            {#snippet child({ props })}
              <Button
                size="icon"
                variant="ghost"
                class="viewer-control"
                {...props}
                onclick={(event) => {
                  props.onclick?.(event);
                  onZoomOut();
                }}
                aria-label="Zoom out"
              >
                <Minus size={16} />
              </Button>
            {/snippet}
          </TooltipTrigger>
          <TooltipContent side="bottom">{TOOLTIP_COPY.zoomOut}</TooltipContent>
        </Tooltip>
        <span class="viewer-scale">{Math.round((isPdf ? normalizedScale : scale) * 100)}%</span>
        <Tooltip disabled={!tooltipsEnabled}>
          <TooltipTrigger>
            {#snippet child({ props })}
              <Button
                size="icon"
                variant="ghost"
                class="viewer-control"
                {...props}
                onclick={(event) => {
                  props.onclick?.(event);
                  onZoomIn();
                }}
                aria-label="Zoom in"
              >
                <Plus size={16} />
              </Button>
            {/snippet}
          </TooltipTrigger>
          <TooltipContent side="bottom">{TOOLTIP_COPY.zoomIn}</TooltipContent>
        </Tooltip>
        <div class="viewer-divider"></div>
        <span class="viewer-control" data-active={fitMode === 'height'}>
          <Tooltip disabled={!tooltipsEnabled}>
            <TooltipTrigger>
              {#snippet child({ props })}
                <Button
                  size="icon"
                  variant="ghost"
                  {...props}
                  onclick={(event) => {
                    props.onclick?.(event);
                    onSetFitMode('height');
                  }}
                  aria-label="Fit to height"
                >
                  <GalleryVertical size={16} />
                </Button>
              {/snippet}
            </TooltipTrigger>
            <TooltipContent side="bottom">{TOOLTIP_COPY.fitHeight}</TooltipContent>
          </Tooltip>
        </span>
        <span class="viewer-control" data-active={fitMode === 'width'}>
          <Tooltip disabled={!tooltipsEnabled}>
            <TooltipTrigger>
              {#snippet child({ props })}
                <Button
                  size="icon"
                  variant="ghost"
                  {...props}
                  onclick={(event) => {
                    props.onclick?.(event);
                    onSetFitMode('width');
                  }}
                  aria-label="Fit to width"
                >
                  <GalleryHorizontal size={16} />
                </Button>
              {/snippet}
            </TooltipTrigger>
            <TooltipContent side="bottom">{TOOLTIP_COPY.fitWidth}</TooltipContent>
          </Tooltip>
        </span>
      </div>
    {/if}
    <div class="viewer-standard-actions">
      {#if isPdf && viewMode !== 'markdown'}
        <div class="viewer-divider"></div>
      {/if}
      <Tooltip disabled={!tooltipsEnabled}>
        <TooltipTrigger>
          {#snippet child({ props })}
            <Button
              size="icon"
              variant="ghost"
              class="viewer-control"
              {...props}
              onclick={(event) => {
                props.onclick?.(event);
                onPinToggle();
              }}
              disabled={!hasActive}
              aria-label="Pin file"
            >
              {#if isPinned}
                <PinOff size={16} />
              {:else}
                <Pin size={16} />
              {/if}
            </Button>
          {/snippet}
        </TooltipTrigger>
        <TooltipContent side="bottom">{pinTooltip}</TooltipContent>
      </Tooltip>
      <Tooltip disabled={!tooltipsEnabled}>
        <TooltipTrigger>
          {#snippet child({ props })}
            <Button
              size="icon"
              variant="ghost"
              class="viewer-control"
              aria-label="Rename file"
              {...props}
              onclick={(event) => {
                props.onclick?.(event);
                onRename();
              }}
              disabled={!hasActive}
            >
              <Pencil size={16} />
            </Button>
          {/snippet}
        </TooltipTrigger>
        <TooltipContent side="bottom">{TOOLTIP_COPY.rename}</TooltipContent>
      </Tooltip>
      <Tooltip disabled={!tooltipsEnabled}>
        <TooltipTrigger>
          {#snippet child({ props })}
            <Button
              size="icon"
              variant="ghost"
              class="viewer-control"
              {...props}
              onclick={(event) => {
                props.onclick?.(event);
                onDownload();
              }}
              disabled={!viewerUrl || isVideo}
              aria-label={isSpreadsheet ? 'Download CSV' : 'Download file'}
            >
              <Download size={16} />
            </Button>
          {/snippet}
        </TooltipTrigger>
        <TooltipContent side="bottom">{downloadLabel}</TooltipContent>
      </Tooltip>
      <Tooltip disabled={!tooltipsEnabled}>
        <TooltipTrigger>
          {#snippet child({ props })}
            <Button
              size="icon"
              variant="ghost"
              class="viewer-control"
              {...props}
              onclick={(event) => {
                props.onclick?.(event);
                onCopyMarkdown();
              }}
              disabled={!hasMarkdown && !isSpreadsheet}
              aria-label={isSpreadsheet ? 'Copy CSV' : 'Copy markdown'}
            >
              {#if isCopied}
                <Check size={16} />
              {:else}
                <Copy size={16} />
              {/if}
            </Button>
          {/snippet}
        </TooltipTrigger>
        <TooltipContent side="bottom">
          {hasMarkdown || isSpreadsheet ? copyTooltip : 'Markdown not available'}
        </TooltipContent>
      </Tooltip>
      <Tooltip disabled={!tooltipsEnabled}>
        <TooltipTrigger>
          {#snippet child({ props })}
            <Button
              size="icon"
              variant="ghost"
              class="viewer-control"
              {...props}
              onclick={(event) => {
                props.onclick?.(event);
                onDelete();
              }}
              disabled={!hasActive}
              aria-label="Delete file"
            >
              <Trash2 size={16} />
            </Button>
          {/snippet}
        </TooltipTrigger>
        <TooltipContent side="bottom">{TOOLTIP_COPY.delete}</TooltipContent>
      </Tooltip>
      <Tooltip disabled={!tooltipsEnabled}>
        <TooltipTrigger>
          {#snippet child({ props })}
            <Button
              size="icon"
              variant="ghost"
              class="viewer-close"
              {...props}
              onclick={(event) => {
                props.onclick?.(event);
                onClose();
              }}
              aria-label="Close file viewer"
            >
              <X size={16} />
            </Button>
          {/snippet}
        </TooltipTrigger>
        <TooltipContent side="bottom">{TOOLTIP_COPY.close}</TooltipContent>
      </Tooltip>
    </div>
    <div class="viewer-standard-compact">
      <Popover.Root>
        <Popover.Trigger>
          {#snippet child({ props: popoverProps })}
            <Tooltip disabled={!tooltipsEnabled}>
              <TooltipTrigger>
                {#snippet child({ props: tooltipProps })}
                  <Button
                    size="icon"
                    variant="ghost"
                    {...popoverProps}
                    {...tooltipProps}
                    aria-label="More actions"
                  >
                    <Menu size={16} />
                  </Button>
                {/snippet}
              </TooltipTrigger>
              <TooltipContent side="bottom">{TOOLTIP_COPY.moreActions}</TooltipContent>
            </Tooltip>
          {/snippet}
        </Popover.Trigger>
        <Popover.Content class="viewer-actions-menu" align="end" sideOffset={8}>
          {#if isPdf}
            <div class="viewer-menu-label">Page {currentPage} / {pageCount || 1}</div>
            <div class="viewer-menu-row">
              <button class="viewer-menu-item" onclick={onPrevPage} disabled={!canPrev}>
                <ChevronLeft size={16} />
                <span>Prev page</span>
              </button>
              <button class="viewer-menu-item" onclick={onNextPage} disabled={!canNext}>
                <ChevronRight size={16} />
                <span>Next page</span>
              </button>
            </div>
            <div class="viewer-menu-label">Zoom {Math.round((isPdf ? normalizedScale : scale) * 100)}%</div>
            <div class="viewer-menu-row">
              <button class="viewer-menu-item" onclick={onZoomOut}>
                <Minus size={16} />
                <span>Zoom out</span>
              </button>
              <button class="viewer-menu-item" onclick={onZoomIn}>
                <Plus size={16} />
                <span>Zoom in</span>
              </button>
            </div>
            <div class="viewer-menu-row">
              <button class="viewer-menu-item" onclick={() => onSetFitMode('height')}>
                <GalleryVertical size={16} />
                <span>Fit height</span>
              </button>
              <button class="viewer-menu-item" onclick={() => onSetFitMode('width')}>
                <GalleryHorizontal size={16} />
                <span>Fit width</span>
              </button>
            </div>
            <div class="viewer-menu-divider"></div>
          {/if}
          <button class="viewer-menu-item" onclick={onPinToggle} disabled={!hasActive}>
            {#if isPinned}
              <PinOff size={16} />
              <span>Unpin</span>
            {:else}
              <Pin size={16} />
              <span>Pin</span>
            {/if}
          </button>
          <button class="viewer-menu-item" onclick={onRename} disabled={!hasActive}>
            <Pencil size={16} />
            <span>Rename</span>
          </button>
          <button class="viewer-menu-item" onclick={onDownload} disabled={!viewerUrl || isVideo}>
            <Download size={16} />
            <span>{isSpreadsheet ? 'Download CSV' : 'Download'}</span>
          </button>
          <button class="viewer-menu-item" onclick={onCopyMarkdown} disabled={!hasMarkdown && !isSpreadsheet}>
            {#if isCopied}
              <Check size={16} />
              <span>Copied</span>
            {:else}
              <Copy size={16} />
              <span>{isSpreadsheet ? 'Copy CSV' : 'Copy'}</span>
            {/if}
          </button>
          <button class="viewer-menu-item" onclick={onDelete} disabled={!hasActive}>
            <Trash2 size={16} />
            <span>Delete</span>
          </button>
          <button class="viewer-menu-item" onclick={onClose}>
            <X size={16} />
            <span>Close</span>
          </button>
        </Popover.Content>
      </Popover.Root>
    </div>
  </div>
</div>

<style>
  .file-viewer-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.63rem 1.2rem;
    border-bottom: 1px solid var(--color-border);
    gap: 1rem;
    container-type: inline-size;
    position: relative;
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

  .file-viewer-controls {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
  }

  .viewer-toggle-center {
    position: absolute;
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    justify-content: center;
  }

  .viewer-toggle-compact {
    display: none;
  }

  .viewer-toggle {
    display: inline-flex;
    align-items: center;
    border: 1px solid var(--color-border);
    border-radius: 999px;
    overflow: hidden;
  }

  .viewer-toggle--compact {
    border-radius: 0.6rem;
  }

  .viewer-toggle-button {
    border: none;
    background: transparent;
    padding: 0.25rem 0.5rem;
    font-size: 0.7rem;
    cursor: pointer;
    color: var(--color-muted-foreground);
    display: inline-flex;
    align-items: center;
    justify-content: center;
  }

  .viewer-toggle-button.active {
    color: var(--color-foreground);
    background: var(--color-sidebar-accent);
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

  .pdf-controls-inline.hidden {
    display: none;
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

  @container (max-width: 700px) {
    .viewer-toggle-center {
      display: none;
    }

    .viewer-toggle-compact {
      display: inline-flex;
    }

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