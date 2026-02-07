const YOUTUBE_ID_PATTERN = /^[A-Za-z0-9_-]{6,}$/;

function normalizeYouTubeHost(hostname: string): string {
	return hostname.trim().toLowerCase().replace(/\.$/, '');
}

export function isYouTubeHost(hostname: string): boolean {
	const host = normalizeYouTubeHost(hostname);
	return (
		host === 'youtube.com' ||
		host.endsWith('.youtube.com') ||
		host === 'youtu.be' ||
		host.endsWith('.youtu.be')
	);
}

export function isValidYouTubeVideoId(videoId: string): boolean {
	return YOUTUBE_ID_PATTERN.test(videoId.trim());
}

export function extractYouTubeVideoId(raw: string): string | null {
	const trimmed = raw.trim();
	if (!trimmed) return null;
	const candidate = /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
	let parsed: URL;
	try {
		parsed = new URL(candidate);
	} catch {
		return null;
	}

	if (!isYouTubeHost(parsed.hostname)) return null;

	const host = normalizeYouTubeHost(parsed.hostname);
	const pathParts = parsed.pathname.split('/').filter(Boolean);

	if (host === 'youtu.be' || host.endsWith('.youtu.be')) {
		const videoId = pathParts[0] ?? '';
		return isValidYouTubeVideoId(videoId) ? videoId : null;
	}

	const queryVideoId = parsed.searchParams.get('v');
	if (queryVideoId && isValidYouTubeVideoId(queryVideoId)) {
		return queryVideoId;
	}

	if (pathParts.length >= 2 && ['embed', 'shorts', 'live', 'v'].includes(pathParts[0])) {
		const videoId = pathParts[1] ?? '';
		return isValidYouTubeVideoId(videoId) ? videoId : null;
	}

	return null;
}

export function buildYouTubeNoCookieEmbedUrl(raw: string): string | null {
	const videoId = extractYouTubeVideoId(raw);
	if (!videoId) return null;
	return `https://www.youtube-nocookie.com/embed/${videoId}`;
}
