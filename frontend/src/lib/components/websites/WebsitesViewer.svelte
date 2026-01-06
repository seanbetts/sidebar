<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { Editor } from '@tiptap/core';
  import StarterKit from '@tiptap/starter-kit';
  import Youtube from '@tiptap/extension-youtube';
  import { ImageGallery } from '$lib/components/editor/ImageGallery';
  import { ImageWithCaption } from '$lib/components/editor/ImageWithCaption';
  import { VimeoEmbed } from '$lib/components/editor/VimeoEmbed';
  import { TaskList, TaskItem } from '@tiptap/extension-list';
  import { TableKit } from '@tiptap/extension-table';
  import { Markdown } from 'tiptap-markdown';
  import { websitesStore } from '$lib/stores/websites';
  import DeleteDialogController from '$lib/components/files/DeleteDialogController.svelte';
  import WebsiteHeader from '$lib/components/websites/WebsiteHeader.svelte';
  import WebsiteRenameDialog from '$lib/components/websites/WebsiteRenameDialog.svelte';
  import { logError } from '$lib/utils/errorHandling';
  import { useWebsiteActions } from '$lib/hooks/useWebsiteActions';

  let editorElement: HTMLDivElement;
  let editor: Editor | null = null;
  let isRenameDialogOpen = false;
  let renameValue = '';
  let deleteDialog: { openDialog: (name: string) => void } | null = null;
  let copyTimeout: ReturnType<typeof setTimeout> | null = null;
  let isCopied = false;
  const { renameWebsite, pinWebsite, archiveWebsite, deleteWebsite } = useWebsiteActions();

  function formatDateWithOrdinal(date: Date) {
    const day = date.getDate();
    const suffix = day % 100 >= 11 && day % 100 <= 13
      ? 'th'
      : day % 10 === 1
        ? 'st'
        : day % 10 === 2
          ? 'nd'
          : day % 10 === 3
            ? 'rd'
            : 'th';
    const month = date.toLocaleDateString(undefined, { month: 'long' });
    const year = date.getFullYear();
    return `${day}${suffix} ${month} ${year}`;
  }

  function formatDomain(domain: string) {
    return domain.replace(/^www\./i, '');
  }

  onMount(() => {
    editor = new Editor({
      element: editorElement,
      extensions: [
        StarterKit,
        Youtube.configure({
          controls: true,
          modestBranding: true,
          HTMLAttributes: {
            class: 'video-embed'
          }
        }),
        VimeoEmbed,
        ImageGallery,
        ImageWithCaption.configure({ inline: false, allowBase64: true }),
        TaskList,
        TaskItem.configure({ nested: true }),
        TableKit,
        Markdown.configure({ html: true })
      ],
      content: '',
      editable: false,
      editorProps: {
        attributes: {
          class: 'tiptap website-viewer'
        }
      }
    });
  });

  onDestroy(() => {
    if (editor) editor.destroy();
    if (copyTimeout) clearTimeout(copyTimeout);
  });

  $: if (editor && $websitesStore.active) {
    const raw = stripFrontmatter($websitesStore.active.content || '');
    editor.commands.setContent(rewriteVideoEmbeds(raw));
  }

  function stripFrontmatter(text: string): string {
    const trimmed = text.trim();
    if (!trimmed.startsWith('---')) return text;
    const match = trimmed.match(/^---\s*\n[\s\S]*?\n---\s*\n?/);
    if (match) return trimmed.slice(match[0].length);
    const lines = trimmed.split('\n');
    const separatorIndex = lines.findIndex((line) => line.trim() === '---');
    if (separatorIndex >= 0) return lines.slice(separatorIndex + 1).join('\n');
    return text;
  }

  function buildYouTubeEmbed(url: string): string | null {
    try {
      const parsed = new URL(url);
      if (!parsed.hostname.includes('youtube.com') && !parsed.hostname.includes('youtu.be')) {
        return null;
      }
      let videoId: string | null = null;
      if (parsed.hostname.includes('youtu.be')) {
        videoId = parsed.pathname.replace('/', '') || null;
      } else {
        videoId = parsed.searchParams.get('v');
        if (!videoId && parsed.pathname.startsWith('/shorts/')) {
          const parts = parsed.pathname.split('/');
          videoId = parts[2] ?? null;
        }
      }
      if (!videoId) return null;
      return `https://www.youtube-nocookie.com/embed/${videoId}`;
    } catch {
      return null;
    }
  }

  function buildVimeoEmbed(url: string): string | null {
    try {
      const parsed = new URL(url);
      if (!parsed.hostname.includes('vimeo.com')) {
        return null;
      }
      if (parsed.hostname.includes('player.vimeo.com')) {
        return parsed.toString();
      }
      const match = parsed.pathname.match(/\/(\d+)/);
      if (!match) return null;
      return `https://player.vimeo.com/video/${match[1]}`;
    } catch {
      return null;
    }
  }

  function rewriteVideoEmbeds(markdown: string): string {
    const youtubePattern = /^\[YouTube\]\(([^)]+)\)$/gm;
    const vimeoPattern = /^\[Vimeo\]\(([^)]+)\)$/gm;
    const bareUrlPattern = /^(https?:\/\/[^\s]+)$/gm;

    let updated = markdown.replace(youtubePattern, (_, url: string) => {
      const embed = buildYouTubeEmbed(url.trim());
      return embed ? `<div data-youtube-video><iframe src="${embed}"></iframe></div>` : _;
    });

    updated = updated.replace(vimeoPattern, (_, url: string) => {
      const embed = buildVimeoEmbed(url.trim());
      return embed ? `<iframe src="${embed}"></iframe>` : _;
    });

    updated = updated.replace(bareUrlPattern, (match: string) => {
      const youtube = buildYouTubeEmbed(match.trim());
      if (youtube) {
        return `<div data-youtube-video><iframe src="${youtube}"></iframe></div>`;
      }
      const vimeo = buildVimeoEmbed(match.trim());
      return vimeo ? `<iframe src="${vimeo}"></iframe>` : match;
    });

    return updated;
  }

  function openRenameDialog() {
    if (!$websitesStore.active) return;
    renameValue = $websitesStore.active.title || '';
    isRenameDialogOpen = true;
  }

  async function handleRename() {
    const active = $websitesStore.active;
    if (!active) return;
    const trimmed = renameValue.trim();
    if (!trimmed || trimmed === active.title) {
      isRenameDialogOpen = false;
      return;
    }
    const renamed = await renameWebsite(active.id, trimmed, {
      scope: 'websitesViewer.rename',
      updateActive: true
    });
    if (renamed) {
      isRenameDialogOpen = false;
    }
  }

  async function handlePinToggle() {
    const active = $websitesStore.active;
    if (!active) return;
    await pinWebsite(active.id, !active.pinned, {
      scope: 'websitesViewer.pin',
      updateActive: true
    });
  }

  async function handleArchive() {
    const active = $websitesStore.active;
    if (!active) return;
    await archiveWebsite(active.id, !active.archived, {
      scope: 'websitesViewer.archive',
      updateActive: true,
      clearActiveOnArchive: true
    });
  }

  async function handleDownload() {
    const active = $websitesStore.active;
    if (!active) return;
    const link = document.createElement('a');
    link.href = `/api/v1/websites/${active.id}/download`;
    link.download = `${active.title || 'website'}.md`;
    document.body.appendChild(link);
    link.click();
    link.remove();
  }

  async function handleCopy() {
    const active = $websitesStore.active;
    if (!active) return;
    try {
      await navigator.clipboard.writeText(stripFrontmatter(active.content || ''));
      isCopied = true;
      if (copyTimeout) clearTimeout(copyTimeout);
      copyTimeout = setTimeout(() => {
        isCopied = false;
        copyTimeout = null;
      }, 1500);
    } catch (error) {
      logError('Failed to copy website content', error, {
        scope: 'websitesViewer.copy',
        websiteId: active.id
      });
    }
  }

  async function handleDelete(): Promise<boolean> {
    const active = $websitesStore.active;
    if (!active) return false;
    return deleteWebsite(active.id, {
      scope: 'websitesViewer.delete',
      clearActiveOnDelete: true
    });
  }

  function requestDelete() {
    const active = $websitesStore.active;
    if (!active) return;
    deleteDialog?.openDialog(active.title || 'website');
  }

  function handleClose() {
    websitesStore.clearActive();
  }

</script>

<WebsiteRenameDialog
  bind:open={isRenameDialogOpen}
  bind:value={renameValue}
  onConfirm={handleRename}
  onCancel={() => (isRenameDialogOpen = false)}
/>

<DeleteDialogController
  bind:this={deleteDialog}
  itemType="website"
  onConfirm={handleDelete}
/>

<div class="website-pane">
  <WebsiteHeader
    website={$websitesStore.active}
    {isCopied}
    {formatDomain}
    formatDate={formatDateWithOrdinal}
    onPinToggle={handlePinToggle}
    onRename={openRenameDialog}
    onCopy={handleCopy}
    onDownload={handleDownload}
    onArchive={handleArchive}
    onDelete={requestDelete}
    onClose={handleClose}
  />
  <div class="website-body">
    <div bind:this={editorElement} class="website-content"></div>
  </div>
</div>

<style>
  .website-pane {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
  }

  .website-body {
    flex: 1;
    min-height: 0;
    overflow: auto;
    padding: 1.5rem 2rem 2rem;
  }

  .website-content {
    max-width: 856px;
    margin: 0 auto;
  }

  :global(.website-viewer [contenteditable='false']:focus) {
    outline: none;
  }

  :global(.website-viewer a) {
    cursor: pointer;
  }

  :global(.tiptap.website-viewer a:hover) {
    opacity: 0.7;
  }

  :global(.website-viewer table) {
    width: 100%;
    border-collapse: collapse;
    margin: 1em 0;
    font-size: 0.95em;
  }

  :global(.website-viewer th),
  :global(.website-viewer td) {
    border: 1px solid var(--color-border);
    padding: 0em 0.75em;
    text-align: left;
    vertical-align: top;
  }

  :global(.website-viewer thead th) {
    background-color: var(--color-muted);
    color: var(--color-foreground);
    font-weight: 600;
  }

  :global(.website-viewer tbody tr:nth-child(even)) {
    background-color: color-mix(in oklab, var(--color-muted) 40%, transparent);
  }

  /* Code styling */
  :global(.website-viewer code) {
    font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Courier New', monospace;
    font-size: 0.9em;
    background: var(--color-muted);
    padding: 0.15em 0.4em;
    border-radius: 0.25rem;
  }

  :global(.website-viewer pre) {
    background: var(--color-muted);
    padding: 1em;
    border-radius: 0.5rem;
    overflow-x: auto;
    margin: 1em 0;
  }

  :global(.website-viewer pre code) {
    background: none;
    padding: 0;
    font-size: 0.875em;
    line-height: 1.5;
  }

  /* Heading hierarchy - use higher specificity to override .tiptap styles */
  :global(.tiptap.website-viewer h1) {
    font-size: 2em;
    font-weight: 700;
    margin: 0.67em 0 !important;
  }

  :global(.tiptap.website-viewer h2) {
    font-size: 1.5em;
    font-weight: 600;
    margin: 0.75em 0 !important;
  }

  :global(.tiptap.website-viewer h3) {
    font-size: 1.17em;
    font-weight: 600;
    margin: 0.83em 0 !important;
  }

  :global(.tiptap.website-viewer h4),
  :global(.tiptap.website-viewer h5),
  :global(.tiptap.website-viewer h6) {
    font-weight: 600;
    margin: 0.83em 0 !important;
  }

  /* Blockquote accent */
  :global(.tiptap.website-viewer blockquote) {
    border-left: 3px solid var(--color-border);
    padding-left: 1em;
    margin: 1em 0 !important;
    color: var(--color-muted-foreground);
  }

  /* Hide empty paragraphs with only ProseMirror trailing breaks */
  :global(.website-viewer p:has(> br.ProseMirror-trailingBreak:only-child)) {
    display: none;
  }

  /* Center images by default - higher specificity to override app.css */
  :global(.tiptap.website-viewer img) {
    display: block !important;
    margin-left: auto;
    margin-right: auto;
    max-width: 720px;
    max-height: 500px;
  }

  /* Image gallery grid - force 2 images per row */
  :global(.tiptap.website-viewer .image-gallery-grid) {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: 0.5rem;
  }

  :global(.tiptap.website-viewer .image-gallery-grid img) {
    display: block;
    margin: 0;
    width: 49% !important;
    flex: 0 0 49% !important;
    max-width: none !important;
    max-height: 500px !important;
  }

  /* Hide ProseMirror gap cursor in image galleries */
  :global(.website-viewer .image-gallery-grid .ProseMirror-gapcursor) {
    display: none;
  }

</style>
