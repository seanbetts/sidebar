<script lang="ts">
  import { AlertTriangle, FileMusic } from 'lucide-svelte';
  import SpreadsheetViewer from '$lib/components/files/SpreadsheetViewer.svelte';
  import FileMarkdown from '$lib/components/files/FileMarkdown.svelte';

  export let loading = false;
  export let error = '';
  export let viewerUrl: string | null = null;
  export let viewMode: 'content' | 'markdown' = 'content';
  export let isPdf = false;
  export let isSpreadsheet = false;
  export let isAudio = false;
  export let isText = false;
  export let isVideo = false;
  export let isInProgress = false;
  export let isFailed = false;
  export let statusMessage = '';
  export let videoEmbedUrl: string | null = null;
  export let hasMarkdown = false;
  export let markdownLoading = false;
  export let markdownError = '';
  export let markdownContent = '';
  export let isTextLoading = false;
  export let textError = '';
  export let textContent = '';
  export let displayName = '';
  export let filename = 'File';
  export let fitMode: 'auto' | 'width' | 'height' = 'height';
  export let centerPdfPages = false;
  export let effectiveScale = 1;
  export let normalizedScale = 1;
  export let currentPage = 1;
  export let pageCount = 0;
  export let scale = 1;
  export let PdfViewerComponent: typeof import('$lib/components/files/PdfViewer.svelte').default | null = null;
  export let onRegisterSpreadsheetActions:
    | ((actions: { copy: () => void; download: () => void }) => void)
    | null = null;
</script>

<div
  class="file-viewer-body"
  class:audio-body={isAudio}
  class:video-body={isVideo}
  class:markdown-body={viewMode === 'markdown'}
>
  {#if loading}
    <div class="viewer-placeholder">Loading file…</div>
  {:else if error}
    <div class="viewer-placeholder">{error}</div>
  {:else if isVideo}
    <div class="file-viewer-video-content">
      <div class="file-viewer-video-card">
        {#if videoEmbedUrl}
          <div class="file-viewer-video-frame">
            <iframe
              class="file-viewer-video-embed"
              src={videoEmbedUrl}
              title={filename}
              allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
              allowfullscreen
            ></iframe>
          </div>
        {:else}
          <div class="viewer-placeholder">Video unavailable.</div>
        {/if}
      </div>
      {#if isInProgress || isFailed}
        <div class="viewer-placeholder video-status">
          <div class="viewer-placeholder-stack">
            {#if isInProgress}
              <span class="viewer-spinner" aria-hidden="true"></span>
            {:else}
              <span class="viewer-placeholder-alert">
                <AlertTriangle size={20} />
              </span>
            {/if}
            <span>{statusMessage}</span>
          </div>
        </div>
      {/if}
      {#if hasMarkdown}
        {#if markdownLoading}
          <div class="viewer-placeholder video-markdown-status">Loading markdown…</div>
        {:else if markdownError}
          <div class="viewer-placeholder video-markdown-status">{markdownError}</div>
        {:else}
          <div class="file-markdown-container file-markdown-container--media">
            <FileMarkdown content={markdownContent} />
          </div>
        {/if}
      {/if}
    </div>
  {:else if !viewerUrl}
    <div class="viewer-placeholder">
      {#if isFailed}
        <div class="viewer-placeholder-stack">
          <span class="viewer-placeholder-alert">
            <AlertTriangle size={20} />
          </span>
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
  {:else}
    {#if isPdf}
      <div class="viewer-pane" class:viewer-hidden={viewMode === 'markdown'}>
        {#if PdfViewerComponent}
          <svelte:component
            this={PdfViewerComponent}
            src={viewerUrl}
            fitMode={fitMode}
            centerPages={centerPdfPages}
            bind:effectiveScale
            bind:normalizedScale
            bind:currentPage
            bind:pageCount
            bind:scale
          />
        {:else}
          <div class="viewer-placeholder">Loading PDF…</div>
        {/if}
      </div>
      {#if viewMode === 'markdown'}
        {#if markdownLoading}
          <div class="viewer-placeholder">Loading markdown…</div>
        {:else if markdownError}
          <div class="viewer-placeholder">{markdownError}</div>
        {:else}
          <div class="file-markdown-container">
            <FileMarkdown content={markdownContent} />
          </div>
        {/if}
      {/if}
    {:else if viewMode === 'markdown'}
      {#if markdownLoading}
        <div class="viewer-placeholder">Loading markdown…</div>
      {:else if markdownError}
        <div class="viewer-placeholder">{markdownError}</div>
      {:else}
        <div class="file-markdown-container">
          <FileMarkdown content={markdownContent} />
        </div>
      {/if}
    {:else if isSpreadsheet}
      <SpreadsheetViewer
        src={viewerUrl}
        filename={displayName}
        registerActions={(actions) => onRegisterSpreadsheetActions?.(actions)}
      />
    {:else if isAudio}
      <div class="file-viewer-audio-content">
        <div class="file-viewer-audio-card">
          <span class="file-viewer-audio-icon">
            <FileMusic size={40} />
          </span>
          <audio class="file-viewer-audio" controls src={viewerUrl}>
            Your browser does not support the audio element.
          </audio>
        </div>
        {#if hasMarkdown}
          {#if markdownLoading}
            <div class="viewer-placeholder audio-markdown-status">Loading markdown…</div>
          {:else if markdownError}
            <div class="viewer-placeholder audio-markdown-status">{markdownError}</div>
          {:else}
            <div class="file-markdown-container file-markdown-container--media">
              <FileMarkdown content={markdownContent} />
            </div>
          {/if}
        {/if}
      </div>
    {:else if isText}
      {#if isTextLoading}
        <div class="viewer-placeholder">Loading text…</div>
      {:else if textError}
        <div class="viewer-placeholder">{textError}</div>
      {:else}
        <pre class="file-viewer-text">{textContent}</pre>
      {/if}
    {:else}
      <img class="file-viewer-image" src={viewerUrl} alt={filename} />
    {/if}
  {/if}
</div>

<style>
  .file-viewer-body {
    flex: 1;
    min-height: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 1rem;
    background: var(--color-background);
  }

  .file-viewer-body.audio-body,
  .file-viewer-body.video-body,
  .file-viewer-body.markdown-body {
    align-items: flex-start;
    justify-content: center;
    overflow: hidden;
  }

  .viewer-pane {
    flex: 1;
    min-width: 0;
    min-height: 0;
    width: 100%;
    height: 100%;
    display: flex;
  }

  .viewer-hidden {
    display: none !important;
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

  .file-viewer-audio-content {
    width: min(820px, 100%);
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: 1.25rem;
    height: 100%;
    min-height: 0;
  }

  .file-viewer-video-content {
    width: min(900px, 100%);
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
    height: 100%;
    min-height: 0;
  }

  .file-viewer-audio-card,
  .file-viewer-video-card {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.9rem;
    padding: 1.1rem 1.25rem;
    border-radius: 0.75rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
  }

  .file-viewer-audio-card {
    gap: 0.75rem;
  }

  .file-viewer-audio-icon {
    color: var(--color-muted-foreground);
  }

  .file-viewer-audio {
    width: min(520px, 100%);
  }

  .file-viewer-video-frame {
    width: min(720px, 100%);
    aspect-ratio: 16 / 9;
    border-radius: 0.75rem;
    overflow: hidden;
    background: var(--color-background);
    border: 1px solid var(--color-border);
  }

  .file-viewer-video-embed {
    width: 100%;
    height: 100%;
    border: none;
    display: block;
  }

  .audio-markdown-status,
  .video-markdown-status {
    margin-top: 0.5rem;
    text-align: center;
    align-self: center;
  }

  .video-status {
    margin-top: 0.25rem;
    text-align: center;
    align-self: center;
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
    align-self: flex-start;
  }

  .file-markdown-container {
    width: min(960px, 100%);
    max-height: 100%;
    overflow: auto;
    padding: 1rem;
    border-radius: 0.5rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    align-self: flex-start;
  }

  .file-markdown-container--media {
    flex: 1;
    min-height: 0;
    overflow: auto;
    margin: 0 auto;
  }
</style>
