import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const projectRoot = process.cwd();

function readComponentSource(relativePath: string): string {
	return readFileSync(resolve(projectRoot, relativePath), 'utf8');
}

describe('Tiptap lazy loading', () => {
	it('avoids static Tiptap imports in read-only markdown renderers', () => {
		const chatMarkdownSource = readComponentSource('src/lib/components/chat/ChatMarkdown.svelte');
		const fileMarkdownSource = readComponentSource('src/lib/components/files/FileMarkdown.svelte');

		for (const source of [chatMarkdownSource, fileMarkdownSource]) {
			expect(source).not.toMatch(/import\s+(?!type\b)[^;]*from '@tiptap\//);
			expect(source).not.toContain("from 'tiptap-markdown'");
		}
	});
});
