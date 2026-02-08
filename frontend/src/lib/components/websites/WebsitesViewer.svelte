<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import { Editor } from '@tiptap/core';
	import StarterKit from '@tiptap/starter-kit';
	import Youtube from '@tiptap/extension-youtube';
	import Link from '@tiptap/extension-link';
	import { ImageGallery } from '$lib/components/editor/ImageGallery';
	import { ImageWithCaption } from '$lib/components/editor/ImageWithCaption';
	import { VimeoEmbed } from '$lib/components/editor/VimeoEmbed';
	import { TaskList, TaskItem } from '@tiptap/extension-list';
	import { TableKit } from '@tiptap/extension-table';
	import { Markdown } from 'tiptap-markdown';
	import {
		websitesStore,
		type WebsiteDetail,
		type WebsiteTranscriptEntry
	} from '$lib/stores/websites';
	import { transcriptStatusStore } from '$lib/stores/transcript-status';
	import { websitesAPI } from '$lib/services/api';
	import DeleteDialogController from '$lib/components/files/DeleteDialogController.svelte';
	import WebsiteHeader from '$lib/components/websites/WebsiteHeader.svelte';
	import WebsiteRenameDialog from '$lib/components/websites/WebsiteRenameDialog.svelte';
	import { logError } from '$lib/utils/errorHandling';
	import { useWebsiteActions } from '$lib/hooks/useWebsiteActions';
	import { toast } from 'svelte-sonner';
	import { getWebsiteDisplayTitle, stripWebsiteFrontmatter } from '$lib/utils/websites';
	import { extractYouTubeVideoId } from '$lib/utils/youtube';
	import { normalizeHtmlBlocks, rewriteVideoEmbeds } from './viewerEmbedTransforms';
	import { applyTranscriptQueuedState, resetTranscriptLinkState } from './transcriptLinkState';

	let editorElement: HTMLDivElement;
	let editor: Editor | null = null;
	let isRenameDialogOpen = false;
	let renameValue = '';
	let deleteDialog: { openDialog: (name: string) => void } | null = null;
	let copyTimeout: ReturnType<typeof setTimeout> | null = null;
	let isCopied = false;
	const { renameWebsite, pinWebsite, archiveWebsite, deleteWebsite } = useWebsiteActions();

	onMount(() => {
		editor = new Editor({
			element: editorElement,
			extensions: [
				StarterKit.configure({
					link: false
				}),
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
				Link.configure({
					openOnClick: true,
					autolink: true,
					linkOnPaste: true,
					HTMLAttributes: {
						rel: 'noopener noreferrer',
						target: '_blank'
					}
				}),
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
		editorElement?.addEventListener('click', handleTranscriptClick);
	});

	onDestroy(() => {
		if (editor) editor.destroy();
		if (copyTimeout) clearTimeout(copyTimeout);
		editorElement?.removeEventListener('click', handleTranscriptClick);
	});

	$: if (editor && $websitesStore.active) {
		const raw = stripWebsiteFrontmatter($websitesStore.active.content || '');
		const normalized = normalizeHtmlBlocks(raw);
		editor.commands.setContent(
			rewriteVideoEmbeds(normalized, $websitesStore.active, $transcriptStatusStore)
		);
	}

	async function queueTranscript(websiteId: string, url: string): Promise<boolean> {
		try {
			const data = await websitesAPI.transcribeYouTube(websiteId, url);
			if (data && typeof data === 'object') {
				if ('content' in data) {
					websitesStore.updateActiveLocal({ content: (data as { content: string }).content });
					return true;
				}
				const payload = data as { data?: { file_id?: string; status?: string } };
				const fileId = payload?.data?.file_id;
				const status = payload?.data?.status;
				const videoId = extractYouTubeVideoId(url);
				if (fileId && videoId) {
					const active = $websitesStore.active;
					const transcripts = active?.youtube_transcripts ?? {};
					websitesStore.setTranscriptEntryLocal(websiteId, videoId, {
						...(transcripts[videoId] ?? {}),
						status: status ?? 'queued',
						file_id: fileId,
						updated_at: new Date().toISOString()
					});
					transcriptStatusStore.set({
						status: 'processing',
						websiteId,
						videoId,
						fileId
					});
					return true;
				}
			}
			throw new Error('Transcript request failed');
		} catch (error) {
			logError('Failed to transcribe YouTube video', error, {
				scope: 'websitesViewer.transcribe',
				url
			});
			toast.error('Transcript failed', {
				description: 'Please try again.'
			});
			return false;
		}
	}

	async function handleTranscriptClick(event: MouseEvent) {
		const target = event.target as HTMLElement | null;
		const link = target?.closest('a') as HTMLAnchorElement | null;
		const href = link?.getAttribute('href')?.trim();
		if (!link || !href) return;
		let parsedUrl: URL;
		try {
			parsedUrl = new URL(href, window.location.href);
		} catch {
			return;
		}
		if (parsedUrl.searchParams.get('sidebarTranscript') !== '1') return;
		parsedUrl.searchParams.delete('sidebarTranscript');
		const url = parsedUrl.toString();
		const active = $websitesStore.active;
		if (!url || !active) return;

		const videoId = extractYouTubeVideoId(url);
		const transcriptEntry = active?.youtube_transcripts?.[videoId ?? ''] ?? null;
		const isPending = ['queued', 'processing', 'retrying'].includes(transcriptEntry?.status ?? '');
		if (isPending) {
			return;
		}

		event.preventDefault();
		applyTranscriptQueuedState(link);
		const queued = await queueTranscript(active.id, url);
		if (!queued) {
			resetTranscriptLinkState(link);
			return;
		}
		link.removeAttribute('aria-busy');
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
			await navigator.clipboard.writeText(stripWebsiteFrontmatter(active.content || ''));
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

	async function handleCopyUrl() {
		const active = $websitesStore.active;
		if (!active) return;
		const sourceUrl = (active.url_full || active.url || '').trim();
		if (!sourceUrl) return;
		try {
			await navigator.clipboard.writeText(sourceUrl);
			toast.success('URL copied');
		} catch (error) {
			logError('Failed to copy website URL', error, {
				scope: 'websitesViewer.copyUrl',
				websiteId: active.id
			});
		}
	}

	async function handleCopyTitle() {
		const active = $websitesStore.active;
		if (!active) return;
		const title = getWebsiteDisplayTitle(active).trim();
		if (!title) return;
		try {
			await navigator.clipboard.writeText(title);
			toast.success('Title copied');
		} catch (error) {
			logError('Failed to copy website title', error, {
				scope: 'websitesViewer.copyTitle',
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

<DeleteDialogController bind:this={deleteDialog} itemType="website" onConfirm={handleDelete} />

<div class="website-pane">
	<WebsiteHeader
		website={$websitesStore.active}
		{isCopied}
		onPinToggle={handlePinToggle}
		onRename={openRenameDialog}
		onCopy={handleCopy}
		onCopyTitle={handleCopyTitle}
		onCopyUrl={handleCopyUrl}
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

	/* Hide empty paragraphs with only ProseMirror trailing breaks */
	:global(.website-viewer p:has(> br.ProseMirror-trailingBreak:only-child)) {
		display: none;
	}

	/* ========================================================================
	   COMPONENT-SPECIFIC: Larger images for external website content
	   Website viewer allows larger images (500px vs 350px in editor) since
	   external content often includes high-quality visuals that benefit from
	   more screen real estate. Center images by default.
	   ======================================================================== */
	:global(.tiptap.website-viewer img) {
		display: block !important;
		margin-left: auto;
		margin-right: auto;
		max-width: 720px;
		max-height: 500px;
	}

	/* ========================================================================
	   COMPONENT-SPECIFIC: Fixed 2-column gallery layout
	   Forces exactly 2 images per row (49% width each) for consistent
	   presentation in website viewer, unlike the flexible grid in the editor.
	   ======================================================================== */
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

	/* ========================================================================
	   COMPONENT-SPECIFIC: YouTube transcript button system
	   Custom feature for fetching and displaying YouTube video transcripts.
	   Includes multiple states: default, hover, queued (with animated pulse),
	   busy, and disabled. Uses OKLAB color mixing for hover effects.
	   ======================================================================== */
	:global(.website-viewer [data-youtube-video]) {
		display: flex;
		flex-direction: column;
		gap: 0.9rem;
		margin: 1.5rem auto;
		width: 100%;
	}

	:global(.website-viewer [data-youtube-video] iframe) {
		width: 100%;
		aspect-ratio: 16 / 9;
		border: 0;
		border-radius: 0.85rem;
		background: var(--color-muted);
	}

	:global(.website-viewer p > a[href*='sidebarTranscript=1']) {
		display: block;
		width: min(100%, 650px);
		text-align: center;
		border-radius: 0.7rem;
		border: 1px solid var(--color-border);
		background: var(--color-muted);
		color: var(--color-foreground);
		padding: 0.6rem 1rem;
		font-size: 0.95rem;
		font-weight: 600;
		text-transform: uppercase;
		text-decoration: none;
		transition:
			background 160ms ease,
			border-color 160ms ease;
		cursor: pointer;
	}

	:global(.website-viewer p > a[href*='sidebarTranscript=1']:hover) {
		background: color-mix(in oklab, var(--color-muted) 80%, var(--color-foreground) 8%);
		border-color: color-mix(in oklab, var(--color-border) 70%, var(--color-foreground) 12%);
	}

	:global(.website-viewer p > a[href*='sidebarTranscript=1'][aria-disabled='true']:hover) {
		background: var(--color-muted);
		border-color: var(--color-border);
	}

	:global(.website-viewer p > a[href*='sidebarTranscript=1'][aria-busy='true']) {
		opacity: 0.6;
		cursor: default;
	}

	:global(.website-viewer p:has(> a[href*='sidebarTranscript=1'])) {
		margin: 0 auto;
		display: flex;
		justify-content: center;
	}

	:global(.website-viewer a[href*='sidebarTranscript=1'].transcript-queued) {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		flex-direction: row;
		gap: 0.5rem;
		width: min(100%, 650px);
		text-align: center;
		border-radius: 0.7rem;
		border: 1px solid var(--color-border) !important;
		background: var(--color-muted);
		color: var(--color-muted-foreground);
		padding: 0.6rem 1rem;
		font-size: 0.95rem;
		font-weight: 600;
		text-transform: uppercase;
		text-decoration: none;
		pointer-events: none !important;
		cursor: default;
		opacity: 1 !important;
	}

	:global(.website-viewer a.transcript-queued::after) {
		content: '';
		display: inline-block;
		width: 0.5rem;
		height: 0.5rem;
		border-radius: 999px;
		background: #d99a2b;
		animation: transcript-pulse 1.4s ease-in-out infinite;
		order: 2;
	}

	:global(.tiptap.website-viewer a.transcript-queued:hover) {
		opacity: 1 !important;
		background: var(--color-muted) !important;
		border-color: var(--color-border) !important;
	}

	:global(.website-viewer p:has(> [data-youtube-transcript-status='queued'])) {
		margin: 0 auto;
		display: flex;
		justify-content: center;
	}

	@keyframes transcript-pulse {
		0% {
			transform: scale(1);
			opacity: 0.6;
		}
		50% {
			transform: scale(1.2);
			opacity: 1;
		}
		100% {
			transform: scale(1);
			opacity: 0.6;
		}
	}
</style>
