export const SCRATCHPAD_HEADING = '# ✏️ Scratchpad';

/**
 * Remove the scratchpad heading from markdown content.
 *
 * @param markdown - Markdown content that may include the heading.
 * @returns Markdown content without the scratchpad heading.
 */
export function stripHeading(markdown: string): string {
	const trimmed = markdown.trim();
	if (!trimmed.startsWith(SCRATCHPAD_HEADING)) return markdown;
	const withoutHeading = trimmed.slice(SCRATCHPAD_HEADING.length).trimStart();
	return withoutHeading.replace(/^\n+/, '');
}

/**
 * Ensure markdown content is wrapped with the scratchpad heading.
 *
 * @param markdown - Markdown content to wrap.
 * @returns Markdown content with heading and spacing applied.
 */
export function withHeading(markdown: string): string {
	const body = markdown.trim();
	if (!body) return `${SCRATCHPAD_HEADING}\n`;
	return `${SCRATCHPAD_HEADING}\n\n${body}\n`;
}

/**
 * Remove empty task list items from markdown content.
 *
 * @param markdown - Markdown content to clean.
 * @returns Cleaned markdown content.
 */
export function removeEmptyTaskItems(markdown: string): string {
	return markdown.replace(/^\s*[-*]\s+\[ \]\s*$/gm, '').trim();
}
