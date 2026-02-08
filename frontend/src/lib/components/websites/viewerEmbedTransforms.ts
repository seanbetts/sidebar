import type { WebsiteDetail, WebsiteTranscriptEntry } from '$lib/stores/websites';
import { buildYouTubeNoCookieEmbedUrl, extractYouTubeVideoId } from '$lib/utils/youtube';

type TranscriptActiveJob = { websiteId: string; videoId: string } | null;

function hasTranscriptForVideo(markdown: string, videoId: string | null): boolean {
	if (!videoId) return false;
	const marker = `<!-- YOUTUBE_TRANSCRIPT:${videoId} -->`;
	return markdown.includes(marker);
}

function isTranscriptPending(status?: string): boolean {
	return status === 'queued' || status === 'processing' || status === 'retrying';
}

function getTranscriptEntries(
	website: WebsiteDetail | null
): Record<string, WebsiteTranscriptEntry> {
	if (!website || !website.youtube_transcripts) return {};
	return typeof website.youtube_transcripts === 'object' ? website.youtube_transcripts : {};
}

function getTranscriptEntry(
	website: WebsiteDetail | null,
	videoId: string | null
): WebsiteTranscriptEntry | null {
	if (!videoId) return null;
	const entries = getTranscriptEntries(website);
	return entries[videoId] ?? null;
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

function escapeAttribute(value: string): string {
	return value.replace(/"/g, '&quot;');
}

function buildTranscriptHref(url: string): string | null {
	try {
		const parsed = new URL(url);
		parsed.searchParams.set('sidebarTranscript', '1');
		return parsed.toString();
	} catch {
		return null;
	}
}

function buildTranscriptButton(
	markdown: string,
	videoUrl: string,
	website: WebsiteDetail | null,
	activeJob: TranscriptActiveJob
): string {
	const videoId = extractYouTubeVideoId(videoUrl);
	const showButton = !hasTranscriptForVideo(markdown, videoId);
	const transcriptHref = buildTranscriptHref(videoUrl);
	const transcriptEntry = getTranscriptEntry(website, videoId);
	const isQueued =
		isTranscriptPending(transcriptEntry?.status) ||
		(activeJob?.websiteId === website?.id && activeJob?.videoId === videoId);

	if (!showButton || !transcriptHref) return '';
	if (isQueued) {
		return `<a data-youtube-transcript data-youtube-transcript-status="queued" aria-disabled="true" class="transcript-queued" href="${escapeAttribute(transcriptHref)}">Transcribing</a>`;
	}
	return `<a data-youtube-transcript href="${escapeAttribute(transcriptHref)}">Get Transcript</a>`;
}

function stripTranscriptArtifacts(markdown: string): string {
	const withoutMarker = markdown.replace(/^\s*<!--\s*YOUTUBE_TRANSCRIPT:[^>]+-->\s*\n?/gm, '');
	const withoutLegacyTitle = withoutMarker.replace(/^\s*###\s+Transcript of .+ video\s*\n?/gm, '');
	return withoutLegacyTitle.replace(/\n{3,}/g, '\n\n');
}

export function normalizeHtmlBlocks(text: string): string {
	return text.replace(/<\/figure>\n(?!\s*\n)/g, '</figure>\n\n');
}

export function rewriteVideoEmbeds(
	markdown: string,
	website: WebsiteDetail | null,
	activeJob: TranscriptActiveJob
): string {
	const youtubePattern = /^\[YouTube\]\(([^)]+)\)$/gm;
	const vimeoPattern = /^\[Vimeo\]\(([^)]+)\)$/gm;
	const bareUrlPattern = /^(https?:\/\/[^\s]+)$/gm;

	let updated = markdown.replace(youtubePattern, (_, url: string) => {
		const trimmedUrl = url.trim();
		const embed = buildYouTubeNoCookieEmbedUrl(trimmedUrl);
		if (!embed) return _;
		const button = buildTranscriptButton(markdown, trimmedUrl, website, activeJob);
		return `<div data-youtube-video><iframe src="${embed}"></iframe>${button}</div>`;
	});

	updated = updated.replace(vimeoPattern, (_, url: string) => {
		const embed = buildVimeoEmbed(url.trim());
		return embed ? `<iframe src="${embed}"></iframe>` : _;
	});

	updated = updated.replace(bareUrlPattern, (match: string) => {
		const trimmedUrl = match.trim();
		const youtube = buildYouTubeNoCookieEmbedUrl(trimmedUrl);
		if (youtube) {
			const button = buildTranscriptButton(markdown, trimmedUrl, website, activeJob);
			return `<div data-youtube-video><iframe src="${youtube}"></iframe>${button}</div>`;
		}
		const vimeo = buildVimeoEmbed(trimmedUrl);
		return vimeo ? `<iframe src="${vimeo}"></iframe>` : match;
	});

	return stripTranscriptArtifacts(updated);
}
