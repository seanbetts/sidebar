export type WebsiteDisplayLike = {
	title: string;
	url: string;
};

export type WebsiteSourceLike = {
	url: string;
	url_full?: string | null;
};

const secondLevelPrefixes = new Set(['co', 'com', 'org', 'net', 'gov', 'edu', 'ac', 'or']);

/**
 * Return the display title for a website, falling back to URL when title is empty.
 */
export function getWebsiteDisplayTitle(site: WebsiteDisplayLike): string {
	const title = site.title.trim();
	return title.length > 0 ? title : site.url;
}

/**
 * Remove a leading www. prefix from a domain.
 */
export function stripWwwPrefix(domain: string): string {
	return domain.replace(/^www\./i, '');
}

/**
 * Extract a readable base domain with support for common two-part country TLD patterns.
 */
export function extractBaseDomain(domain: string): string {
	const cleaned = stripWwwPrefix(domain);
	const parts = cleaned.split('.').filter(Boolean);
	if (parts.length <= 2) return cleaned;

	const last = parts[parts.length - 1];
	const secondLast = parts[parts.length - 2];
	if (secondLevelPrefixes.has(secondLast.toLowerCase()) && last.length === 2 && parts.length >= 3) {
		return parts.slice(-3).join('.');
	}
	return parts.slice(-2).join('.');
}

/**
 * Format a website subtitle as "domain | reading time" when reading time exists.
 */
export function formatWebsiteSubtitle(domain: string, readingTime?: string | null): string {
	const baseDomain = extractBaseDomain(domain);
	const trimmedReadingTime = readingTime?.trim() ?? '';
	if (trimmedReadingTime.length === 0) {
		return baseDomain;
	}
	return `${baseDomain} | ${trimmedReadingTime}`;
}

/**
 * Return the best source URL for opening a website.
 */
export function getWebsiteSourceUrl(site: WebsiteSourceLike): string {
	const fullUrl = site.url_full?.trim();
	if (fullUrl && fullUrl.length > 0) {
		return fullUrl;
	}
	return site.url;
}

/**
 * Remove markdown frontmatter when present.
 */
export function stripWebsiteFrontmatter(text: string): string {
	const trimmed = text.trim();
	if (!trimmed.startsWith('---')) return text;
	const match = trimmed.match(/^---\s*\n[\s\S]*?\n---\s*\n?/);
	if (match) return trimmed.slice(match[0].length);
	const lines = trimmed.split('\n');
	const separatorIndex = lines.findIndex((line) => line.trim() === '---');
	if (separatorIndex >= 0) return lines.slice(separatorIndex + 1).join('\n');
	return text;
}
