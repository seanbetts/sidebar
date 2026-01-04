<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { browser } from '$app/environment';
  import { ingestionViewerStore } from '$lib/stores/ingestion-viewer';
  import { ingestionAPI } from '$lib/services/api';
  import { dispatchCacheEvent } from '$lib/utils/cacheEvents';
  import { ingestionStore } from '$lib/stores/ingestion';
  import { buildIngestionStatusMessage } from '$lib/utils/ingestionStatus';
  import TextInputDialog from '$lib/components/left-sidebar/dialogs/TextInputDialog.svelte';
  import DeleteDialogController from '$lib/components/files/DeleteDialogController.svelte';
  import UniversalViewerHeader from '$lib/components/files/UniversalViewerHeader.svelte';
  import UniversalViewerBody from '$lib/components/files/UniversalViewerBody.svelte';

  $: active = $ingestionViewerStore.active;
  $: loading = $ingestionViewerStore.loading;
  $: error = $ingestionViewerStore.error;
  $: viewerKind = active?.recommended_viewer;
  $: viewerUrl =
    active && viewerKind && viewerKind !== 'viewer_video'
      ? `/api/v1/ingestion/${active.file.id}/content?kind=${encodeURIComponent(viewerKind)}`
      : null;
  $: isPdf = viewerKind === 'viewer_pdf';
  $: isAudio = viewerKind === 'audio_original';
  $: isText = viewerKind === 'text_original';
  $: isSpreadsheet = viewerKind === 'viewer_json';
  $: isVideo = viewerKind === 'viewer_video';
  $: isImage = active?.file.category === 'images';
  $: isPresentation = active?.file.category === 'presentations';
  $: centerPdfPages = isPresentation || isPdf;
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
  $: showMarkdownToggle = hasMarkdown && !isSpreadsheet && !isAudio && !isVideo;
  $: videoEmbedUrl = isVideo ? buildYouTubeEmbedUrl(active?.file.source_url) : null;

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
  let deleteDialog: { openDialog: (name: string) => void } | null = null;
  let textContent = '';
  let textError = '';
  let isTextLoading = false;
  let lastTextUrl: string | null = null;
  let spreadsheetActions: { copy: () => void; download: () => void } | null = null;
  let viewMode: 'content' | 'markdown' = 'content';
  let markdownContent = '';
  let markdownError = '';
  let markdownLoading = false;
  let lastMarkdownId: string | null = null;
  let isMounted = false;

  $: if (active) {
    const item = $ingestionStore.items.find(entry => entry.file.id === active.file.id);
    if (item && item.job) {
      ingestionViewerStore.updateActiveJob(active.file.id, item.job);
    }
  }
  $: if (!showMarkdownToggle) {
    viewMode = 'content';
  }
  $: if (viewMode === 'markdown' && active?.file.id) {
    if (active.file.id !== lastMarkdownId) {
      loadMarkdown();
    }
  }
  $: if (isAudio && hasMarkdown && active?.file.id) {
    if (active.file.id !== lastMarkdownId) {
      loadMarkdown();
    }
  }
  $: if (isVideo && hasMarkdown && active?.file.id) {
    if (active.file.id !== lastMarkdownId) {
      loadMarkdown();
    }
  }

  onMount(async () => {
    if (!browser) return;
    isMounted = true;
    const module = await import('$lib/components/files/PdfViewer.svelte');
    PdfViewerComponent = module.default;
  });

  onDestroy(() => {
    isMounted = false;
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

  function buildYouTubeEmbedUrl(url: string | null | undefined): string | null {
    if (!url) return null;
    try {
      const normalized = url.startsWith('http://') || url.startsWith('https://')
        ? url
        : `https://${url}`;
      const parsed = new URL(normalized);
      if (!parsed.hostname.includes('youtube.com') && !parsed.hostname.includes('youtu.be')) {
        return null;
      }
      let videoId: string | null = null;
      if (parsed.hostname.includes('youtu.be')) {
        videoId = parsed.pathname.replace('/', '') || null;
      } else {
        videoId = parsed.searchParams.get('v');
        if (!videoId && parsed.pathname.startsWith('/shorts/')) {
          const parts = parsed.pathname.split('/').filter(Boolean);
          videoId = parts[1] ?? null;
        }
      }
      if (!videoId) return null;
      return `https://www.youtube-nocookie.com/embed/${videoId}`;
    } catch {
      return null;
    }
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

  function stripFrontmatter(text: string): string {
    const normalized = text.replace(/\r\n/g, '\n');
    const trimmed = normalized.replace(/^\s+/, '');
    if (trimmed.startsWith('---')) {
      const match = trimmed.match(/^---\s*\n[\s\S]*?\n---\s*\n?/);
      if (!match) return text;
      return trimmed.slice(match[0].length);
    }
    const lines = trimmed.split('\n');
    const separatorIndex = lines.findIndex((line) => line.trim() === '---');
    if (separatorIndex > 0) {
      const metadataLines = lines.slice(0, separatorIndex);
      const allMetadata = metadataLines.every((line) => line.trim() === '' || line.trim().startsWith('#'));
      const hasTranscriptHeader = metadataLines.some((line) =>
        /#\s*(Transcript of|YouTube URL:|Original file:|Generated:)/.test(line)
      );
      if (allMetadata && hasTranscriptHeader) {
        return lines.slice(separatorIndex + 1).join('\n');
      }
    }
    return normalized;
  }

  async function loadMarkdown() {
    if (!active) return;
    markdownLoading = true;
    markdownError = '';
    lastMarkdownId = active.file.id;
    try {
      const response = await ingestionAPI.getContent(active.file.id, 'ai_md');
      let text = await response.text();
      text = stripFrontmatter(text);
      markdownContent = text;
    } catch (error) {
      console.error('Failed to load markdown:', error);
      markdownError = 'Failed to load markdown.';
      markdownContent = '';
    } finally {
      markdownLoading = false;
    }
  }

  function requestDelete() {
    if (!active) return;
    deleteDialog?.openDialog(active.file.filename_original ?? 'file');
  }

  async function confirmDelete(): Promise<boolean> {
    if (!active) return false;
    try {
      await ingestionAPI.delete(active.file.id);
      dispatchCacheEvent('file.deleted');
      ingestionStore.removeItem(active.file.id);
      ingestionViewerStore.clearActive();
      return true;
    } catch (error) {
      console.error('Failed to delete file:', error);
      return false;
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
        'application/msword': 'DOC',
        'application/vnd.ms-powerpoint': 'PPT',
        'application/rtf': 'RTF',
        'text/csv': 'CSV',
        'application/csv': 'CSV',
        'text/tab-separated-values': 'TSV',
        'text/tsv': 'TSV',
        'text/plain': 'TXT',
        'text/markdown': 'MD',
        'text/html': 'HTML',
        'application/json': 'JSON',
        'text/xml': 'XML',
        'application/xml': 'XML',
        'text/javascript': 'JS',
        'application/javascript': 'JS',
        'text/css': 'CSS',
        'application/zip': 'ZIP',
        'application/x-zip-compressed': 'ZIP',
        'application/gzip': 'GZIP',
        'application/epub+zip': 'EPUB',
        'application/vnd.oasis.opendocument.text': 'ODT',
        'application/vnd.oasis.opendocument.spreadsheet': 'ODS'
      } as Record<string, string>;
      if (normalized.startsWith('image/')) {
        const imageSubtype = normalized.split('/')[1] ?? 'image';
        return imageSubtype.toUpperCase();
      }
      if (normalized.startsWith('audio/')) {
        const subtype = normalized.split('/')[1] ?? 'audio';
        const audioPretty = {
          'mpeg': 'MP3',
          'mp3': 'MP3',
          'x-m4a': 'M4A',
          'm4a': 'M4A',
          'x-wav': 'WAV',
          'wav': 'WAV',
          'flac': 'FLAC',
          'ogg': 'OGG'
        } as Record<string, string>;
        return audioPretty[subtype] ?? subtype.replace(/^x-/, '').toUpperCase();
      }
      if (normalized === 'video/youtube') {
        return 'YouTube';
      }
      if (normalized.startsWith('video/')) {
        const subtype = normalized.split('/')[1] ?? 'video';
        return subtype.replace(/^x-/, '').toUpperCase();
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

  $: if (isMounted && browser && isText && viewerUrl && viewerUrl !== lastTextUrl) {
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
  <UniversalViewerHeader
    {isImage}
    {isAudio}
    {isVideo}
    {isSpreadsheet}
    {isPdf}
    {displayName}
    {fileType}
    hasActive={Boolean(active)}
    isPinned={Boolean(active?.file.pinned)}
    {showMarkdownToggle}
    bind:viewMode
    {viewerUrl}
    {hasMarkdown}
    {isCopied}
    {currentPage}
    {pageCount}
    {canPrev}
    {canNext}
    {scale}
    {normalizedScale}
    {fitMode}
    onPrevPage={prevPage}
    onNextPage={nextPage}
    onZoomOut={zoomOut}
    onZoomIn={zoomIn}
    onSetFitMode={setFitMode}
    onPinToggle={handlePinToggle}
    onRename={openRenameDialog}
    onDownload={handleDownload}
    onCopyMarkdown={handleCopyMarkdown}
    onDelete={requestDelete}
    onClose={handleClose}
  />

  <UniversalViewerBody
    {loading}
    {error}
    {viewerUrl}
    viewMode={viewMode}
    {isPdf}
    {isSpreadsheet}
    {isAudio}
    {isText}
    {isVideo}
    {isInProgress}
    {isFailed}
    {statusMessage}
    {videoEmbedUrl}
    {hasMarkdown}
    {markdownLoading}
    {markdownError}
    {markdownContent}
    {isTextLoading}
    {textError}
    {textContent}
    {displayName}
    {filename}
    {fitMode}
    {centerPdfPages}
    bind:effectiveScale
    bind:normalizedScale
    bind:currentPage
    bind:pageCount
    bind:scale
    {PdfViewerComponent}
    onRegisterSpreadsheetActions={(actions) => (spreadsheetActions = actions)}
  />
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

<DeleteDialogController
  bind:this={deleteDialog}
  itemType="file"
  onConfirm={confirmDelete}
/>

<style>
  .file-viewer {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
  }
</style>
