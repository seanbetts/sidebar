export const SCRATCHPAD_HEADING = '# ✏️ Scratchpad';

export function stripHeading(markdown: string): string {
	const trimmed = markdown.trim();
	if (!trimmed.startsWith(SCRATCHPAD_HEADING)) return markdown;
	const withoutHeading = trimmed.slice(SCRATCHPAD_HEADING.length).trimStart();
	return withoutHeading.replace(/^\n+/, '');
}

export function withHeading(markdown: string): string {
	const body = markdown.trim();
	if (!body) return `${SCRATCHPAD_HEADING}\n`;
	return `${SCRATCHPAD_HEADING}\n\n${body}\n`;
}

export function removeEmptyTaskItems(markdown: string): string {
	return markdown.replace(/^\s*[-*]\s+\[ \]\s*$/gm, '').trim();
}
