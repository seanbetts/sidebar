<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { browser } from '$app/environment';

  export let src: string | null = null;
  export let scale = 1;
  export let currentPage = 1;
  export let pageCount = 0;
  export let fitMode: 'auto' | 'width' | 'height' = 'height';

  let pdfjsLib: typeof import('pdfjs-dist') | null = null;

  let container: HTMLDivElement | null = null;
  let canvas: HTMLCanvasElement | null = null;
  let pdfDocument: import('pdfjs-dist').PDFDocumentProxy | null = null;
  let renderTask: import('pdfjs-dist').RenderTask | null = null;
  let loadTask: import('pdfjs-dist').PDFDocumentLoadingTask | null = null;
  let resizeObserver: ResizeObserver | null = null;
  let disposed = false;
  let lastSrc: string | null = null;
  let lastRenderKey = '';
  let containerWidth = 0;
  let containerHeight = 0;
  export let effectiveScale = 1;
  export let normalizedScale = 1;

  onMount(async () => {
    if (!browser) return;
    const [pdfjs, worker] = await Promise.all([
      import('pdfjs-dist'),
      import('pdfjs-dist/build/pdf.worker.min.mjs?url')
    ]);
    pdfjsLib = pdfjs;
    pdfjsLib.GlobalWorkerOptions.workerSrc = worker.default;
    if (container) {
      resizeObserver = new ResizeObserver(([entry]) => {
        if (!entry) return;
        containerWidth = entry.contentRect.width;
        containerHeight = entry.contentRect.height;
        if (pdfDocument) {
          renderPage();
        }
      });
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
    if (loadTask) {
      loadTask.destroy();
    }
    loadTask = pdfjsLib.getDocument({ url: src });
    pdfDocument = await loadTask.promise;
    pageCount = pdfDocument.numPages;
    if (currentPage > pageCount) {
      currentPage = pageCount;
    } else if (currentPage < 1) {
      currentPage = 1;
    }
    lastRenderKey = '';
    await renderPage();
  }

  async function renderPage() {
    if (!pdfDocument || !canvas || disposed) return;
    const page = await pdfDocument.getPage(currentPage);
    const baseViewport = page.getViewport({ scale: 1 });
    let fitScale = 1;
    let heightFitScale = 1;
    if (containerWidth > 0 && containerHeight > 0) {
      heightFitScale = containerHeight / baseViewport.height;
      if (fitMode === 'width') {
        fitScale = containerWidth / baseViewport.width;
      } else if (fitMode === 'height') {
        fitScale = heightFitScale;
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
    const viewport = page.getViewport({ scale: effectiveScale });
    const context = canvas.getContext('2d');
    if (!context) return;
    canvas.width = Math.floor(viewport.width);
    canvas.height = Math.floor(viewport.height);
    renderTask = page.render({ canvasContext: context, viewport });
    try {
      await renderTask.promise;
    } catch (error) {
      // Ignore render cancellations.
    }
  }

  $: if (browser && src && src !== lastSrc) {
    lastSrc = src;
    loadDocument();
  }

  $: if (!src && pdfDocument) {
    pdfDocument = null;
  }

  $: if (browser && pdfDocument) {
    currentPage;
    scale;
    fitMode;
    containerWidth;
    containerHeight;
    renderPage();
  }

  onDestroy(() => {
    disposed = true;
    resizeObserver?.disconnect();
    renderTask?.cancel();
    loadTask?.destroy();
  });
</script>

<div class="pdf-viewer">
  <div class="pdf-viewer-inner" bind:this={container}>
    <canvas bind:this={canvas} class="pdf-canvas"></canvas>
  </div>
</div>

<style>
  .pdf-viewer {
    display: flex;
    justify-content: center;
    align-items: flex-start;
    width: 100%;
    height: 100%;
    overflow: auto;
  }

  .pdf-viewer-inner {
    width: 100%;
    height: 100%;
    display: flex;
    justify-content: center;
    align-items: flex-start;
  }

  .pdf-canvas {
    display: block;
    max-width: 100%;
    height: auto;
  }
</style>
