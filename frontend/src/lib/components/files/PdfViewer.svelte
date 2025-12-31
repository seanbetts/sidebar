<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { browser } from '$app/environment';

  export let src: string | null = null;
  export let scale = 1;
  export let currentPage = 1;
  export let pageCount = 0;
  export let fitMode: 'auto' | 'width' | 'height' = 'height';
  export let centerPages = false;

  let pdfjsLib: typeof import('pdfjs-dist') | null = null;

  let root: HTMLDivElement | null = null;
  let container: HTMLDivElement | null = null;
  let canvas: HTMLCanvasElement | null = null;
  let pdfDocument: import('pdfjs-dist').PDFDocumentProxy | null = null;
  let renderTask: import('pdfjs-dist').RenderTask | null = null;
  let loadTask: import('pdfjs-dist').PDFDocumentLoadingTask | null = null;
  let resizeObserver: ResizeObserver | null = null;
  let thumbnails: Array<{ page: number; url: string }> = [];
  let thumbRefs: Record<number, HTMLButtonElement | null> = {};
  let pageRefs: Record<number, HTMLDivElement | null> = {};
  let pageCanvases: HTMLCanvasElement[] = [];
  let pageRenderTasks = new Map<number, import('pdfjs-dist').RenderTask>();
  let thumbRenderTasks = new Map<number, import('pdfjs-dist').RenderTask>();
  let lastRenderKeys: Record<number, string> = {};
  let disposed = false;
  let lastSrc: string | null = null;
  let lastRenderKey = '';
  let rootWidth = 0;
  let containerWidth = 0;
  let containerHeight = 0;
  let showAllPages = false;
  export let effectiveScale = 1;
  export let normalizedScale = 1;
  const multiPageBreakpoint = 720;

  onMount(async () => {
    if (!browser) return;
    const [pdfjs, worker] = await Promise.all([
      import('pdfjs-dist'),
      import('pdfjs-dist/build/pdf.worker.min.mjs?url')
    ]);
    pdfjsLib = pdfjs;
    pdfjsLib.GlobalWorkerOptions.workerSrc = worker.default;
    pdfjsLib.setVerbosityLevel?.(pdfjsLib.VerbosityLevel.ERRORS);
    if (root || container) {
      resizeObserver = new ResizeObserver((entries) => {
        for (const entry of entries) {
          if (!entry) continue;
          if (entry.target === root) {
            rootWidth = entry.contentRect.width;
            showAllPages = rootWidth > 0 && rootWidth <= multiPageBreakpoint;
          }
          if (entry.target === container) {
            containerWidth = entry.contentRect.width;
            containerHeight = entry.contentRect.height;
          }
        }
        if (pdfDocument) {
          renderPage();
        }
      });
      if (root) resizeObserver.observe(root);
      resizeObserver.observe(container);
    }
    if (src) {
      loadDocument();
    }
  });

  async function loadDocument() {
    if (!browser || !pdfjsLib) return;
    if (!src) return;
    disposed = false;
    thumbnails = [];
    pageRenderTasks.forEach((task) => task.cancel());
    pageRenderTasks.clear();
    thumbRenderTasks.forEach((task) => task.cancel());
    thumbRenderTasks.clear();
    pageCanvases = [];
    pageRefs = {};
    lastRenderKeys = {};
    if (loadTask) {
      loadTask.destroy();
    }
    loadTask = pdfjsLib.getDocument({
      url: src,
      verbosity: pdfjsLib.VerbosityLevel.ERRORS
    });
    pdfDocument = await loadTask.promise;
    pageCount = pdfDocument.numPages;
    if (currentPage > pageCount) {
      currentPage = pageCount;
    } else if (currentPage < 1) {
      currentPage = 1;
    }
    lastRenderKey = '';
    await buildThumbnails();
    await renderPage();
  }

  async function buildThumbnails() {
    if (!browser || !pdfDocument) return;
    const nextThumbs: Array<{ page: number; url: string }> = [];
    const targetWidth = 120;
    for (let pageIndex = 1; pageIndex <= pdfDocument.numPages; pageIndex += 1) {
      if (disposed || !pdfDocument) return;
      const page = await pdfDocument.getPage(pageIndex);
      const baseViewport = page.getViewport({ scale: 1 });
      const thumbScale = targetWidth / baseViewport.width;
      const viewport = page.getViewport({ scale: thumbScale });
      const thumbCanvas = document.createElement('canvas');
      const context = thumbCanvas.getContext('2d');
      if (!context) continue;
      thumbCanvas.width = Math.floor(viewport.width);
      thumbCanvas.height = Math.floor(viewport.height);
      const task = page.render({ canvasContext: context, viewport });
      thumbRenderTasks.set(pageIndex, task);
      try {
        await task.promise;
      } catch (error) {
        if (task.cancelled || disposed) continue;
        continue;
      }
      nextThumbs.push({ page: pageIndex, url: thumbCanvas.toDataURL('image/png') });
    }
    thumbnails = nextThumbs;
    thumbRenderTasks.clear();
  }

  function scrollThumbIntoView(page: number) {
    const target = thumbRefs[page];
    if (!target) return;
    target.scrollIntoView({ block: 'nearest' });
    target.focus({ preventScroll: true });
  }

  function handleThumbKeydown(event: KeyboardEvent) {
    if (!pageCount) return;
    let nextPage = currentPage;
    switch (event.key) {
      case 'ArrowUp':
      case 'ArrowLeft':
        nextPage = Math.max(1, currentPage - 1);
        break;
      case 'ArrowDown':
      case 'ArrowRight':
        nextPage = Math.min(pageCount, currentPage + 1);
        break;
      case 'PageUp':
        nextPage = Math.max(1, currentPage - 5);
        break;
      case 'PageDown':
        nextPage = Math.min(pageCount, currentPage + 5);
        break;
      case 'Home':
        nextPage = 1;
        break;
      case 'End':
        nextPage = pageCount;
        break;
      default:
        return;
    }
    event.preventDefault();
    currentPage = nextPage;
    scrollThumbIntoView(nextPage);
  }

  async function renderPage() {
    if (showAllPages) {
      await renderAllPages();
      return;
    }
    if (!pdfDocument || !canvas || disposed) return;
    const page = await pdfDocument.getPage(currentPage);
    const baseViewport = page.getViewport({ scale: 1 });
    let fitScale = 1;
    let heightFitScale = 1;
    let widthFitScale = 1;
    if (containerWidth > 0 && containerHeight > 0) {
      heightFitScale = containerHeight / baseViewport.height;
      if (fitMode === 'width') {
        fitScale = containerWidth / baseViewport.width;
      } else if (fitMode === 'height') {
        widthFitScale = containerWidth / baseViewport.width;
        fitScale = Math.min(heightFitScale, widthFitScale);
      } else {
        fitScale = Math.min(heightFitScale, containerWidth / baseViewport.width);
      }
    }
    effectiveScale = fitScale * scale;
    normalizedScale = heightFitScale > 0 ? effectiveScale / heightFitScale : scale;
    const renderKey = `${currentPage}-${effectiveScale.toFixed(4)}`;
    if (renderKey === lastRenderKey) return;
    lastRenderKey = renderKey;
    if (renderTask) {
      renderTask.cancel();
    }
    const deviceScale = browser ? window.devicePixelRatio || 1 : 1;
    const viewport = page.getViewport({ scale: effectiveScale });
    const context = canvas.getContext('2d');
    if (!context) return;
    canvas.width = Math.floor(viewport.width * deviceScale);
    canvas.height = Math.floor(viewport.height * deviceScale);
    canvas.style.width = `${Math.floor(viewport.width)}px`;
    canvas.style.height = `${Math.floor(viewport.height)}px`;
    context.setTransform(deviceScale, 0, 0, deviceScale, 0, 0);
    renderTask = page.render({ canvasContext: context, viewport });
    try {
      await renderTask.promise;
    } catch (error) {
      if (renderTask?.cancelled || disposed) return;
      // Ignore render cancellations.
    }
  }

  async function renderAllPages() {
    if (!pdfDocument || disposed) return;
    if (!containerWidth) return;
    for (let pageIndex = 1; pageIndex <= pageCount; pageIndex += 1) {
      if (disposed || !pdfDocument) return;
      const pageCanvas = pageCanvases[pageIndex - 1];
      if (!pageCanvas) continue;
      const page = await pdfDocument.getPage(pageIndex);
      const baseViewport = page.getViewport({ scale: 1 });
      const fitScale = containerWidth / baseViewport.width;
      effectiveScale = fitScale * scale;
      normalizedScale = fitScale > 0 ? effectiveScale / fitScale : scale;
      const renderKey = `${pageIndex}-${effectiveScale.toFixed(4)}`;
      if (lastRenderKeys[pageIndex] === renderKey) continue;
      lastRenderKeys[pageIndex] = renderKey;
      const existingTask = pageRenderTasks.get(pageIndex);
      if (existingTask) {
        existingTask.cancel();
      }
      const deviceScale = browser ? window.devicePixelRatio || 1 : 1;
      const viewport = page.getViewport({ scale: effectiveScale });
      const context = pageCanvas.getContext('2d');
      if (!context) continue;
      pageCanvas.width = Math.floor(viewport.width * deviceScale);
      pageCanvas.height = Math.floor(viewport.height * deviceScale);
      pageCanvas.style.width = `${Math.floor(viewport.width)}px`;
      pageCanvas.style.height = `${Math.floor(viewport.height)}px`;
      context.setTransform(deviceScale, 0, 0, deviceScale, 0, 0);
      const task = page.render({ canvasContext: context, viewport });
      pageRenderTasks.set(pageIndex, task);
      try {
        await task.promise;
      } catch (error) {
        if (task.cancelled || disposed) continue;
        // Ignore render cancellations.
      }
    }
  }

  $: if (browser && src && src !== lastSrc) {
    lastSrc = src;
    loadDocument();
  }

  $: if (!src && pdfDocument) {
    disposed = true;
    pdfDocument?.destroy();
    pdfDocument = null;
    loadTask?.destroy();
    loadTask = null;
    renderTask?.cancel();
    renderTask = null;
    pageRenderTasks.forEach((task) => task.cancel());
    pageRenderTasks.clear();
    thumbRenderTasks.forEach((task) => task.cancel());
    thumbRenderTasks.clear();
  }

  $: if (browser && pdfDocument) {
    currentPage;
    scale;
    fitMode;
    containerWidth;
    containerHeight;
    renderPage();
  }

  $: if (browser && currentPage) {
    scrollThumbIntoView(currentPage);
  }

  $: if (browser && showAllPages && currentPage) {
    const pageRef = pageRefs[currentPage];
    if (pageRef) {
      pageRef.scrollIntoView({ block: 'start' });
    }
  }

  onDestroy(() => {
    disposed = true;
    resizeObserver?.disconnect();
    renderTask?.cancel();
    pageRenderTasks.forEach((task) => task.cancel());
    pageRenderTasks.clear();
    thumbRenderTasks.forEach((task) => task.cancel());
    thumbRenderTasks.clear();
    loadTask?.destroy();
    pdfDocument?.destroy();
  });
</script>

<div class="pdf-viewer" bind:this={root}>
  <div class="pdf-thumbs" tabindex="0" on:keydown={handleThumbKeydown} aria-label="PDF thumbnails">
    {#if thumbnails.length === 0 && pageCount > 0}
      <div class="pdf-thumbs-placeholder">Generating thumbnails…</div>
    {:else}
      {#each thumbnails as thumb}
        <button
          class="pdf-thumb"
          class:active={thumb.page === currentPage}
          bind:this={thumbRefs[thumb.page]}
          on:click={() => (currentPage = thumb.page)}
          aria-label={`Go to page ${thumb.page}`}
        >
          <img src={thumb.url} alt={`Page ${thumb.page}`} />
          <span class="pdf-thumb-label">{thumb.page}</span>
        </button>
      {/each}
    {/if}
  </div>
  <div class="pdf-viewer-main" class:centered={centerPages && !showAllPages} bind:this={container}>
    {#if showAllPages}
      <div class="pdf-pages" class:centered={centerPages && !showAllPages}>
        {#each Array.from({ length: pageCount }, (_, index) => index + 1) as pageNumber (pageNumber)}
          <div class="pdf-page" bind:this={pageRefs[pageNumber]}>
            <canvas bind:this={pageCanvases[pageNumber - 1]} class="pdf-canvas"></canvas>
          </div>
        {/each}
      </div>
    {:else}
      <canvas bind:this={canvas} class="pdf-canvas"></canvas>
    {/if}
  </div>
</div>

<style>
  .pdf-viewer {
    display: flex;
    width: 100%;
    height: 100%;
    overflow: hidden;
    container-type: inline-size;
  }

  .pdf-thumbs {
    width: 140px;
    border-right: 1px solid var(--color-border);
    padding: 0.75rem 0.5rem;
    overflow-y: auto;
    background: var(--color-background);
  }

  .pdf-thumbs-placeholder {
    font-size: 0.75rem;
    color: var(--color-muted-foreground);
    text-align: center;
    padding: 0.5rem;
  }

  .pdf-thumb {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    width: 100%;
    padding: 0.35rem;
    border: 1px solid transparent;
    border-radius: 0.5rem;
    background: transparent;
    cursor: pointer;
    align-items: center;
  }

  .pdf-thumb + .pdf-thumb {
    margin-top: 0.5rem;
  }

  .pdf-thumb img {
    width: 100%;
    height: auto;
    display: block;
    border-radius: 0.35rem;
  }

  .pdf-thumb-label {
    font-size: 0.65rem;
    color: var(--color-muted-foreground);
  }

  .pdf-thumb.active {
    border-color: var(--color-border);
    background: var(--color-sidebar-accent);
  }

  .pdf-viewer-main {
    flex: 1;
    min-width: 0;
    height: 100%;
    display: flex;
    justify-content: center;
    align-items: flex-start;
    overflow: auto;
    padding-left: 1rem;
  }

  .pdf-viewer-main.centered {
    align-items: center;
  }

  .pdf-pages {
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
    padding: 0.5rem 0;
  }

  .pdf-pages.centered {
    align-items: center;
    justify-content: center;
    min-height: 100%;
  }

  .pdf-page {
    display: flex;
    justify-content: center;
  }

  .pdf-canvas {
    display: block;
  }

  @container (max-width: 720px) {
    .pdf-thumbs {
      display: none;
    }

    .pdf-viewer-main {
      width: 100%;
    }
  }
</style>
