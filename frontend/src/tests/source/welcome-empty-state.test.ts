import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const readSource = (path: string) => readFileSync(path, 'utf8');

describe('welcome empty state source checks', () => {
	it('keeps the editor welcome screen focused on the title only', () => {
		const source = readSource('src/lib/components/editor/MarkdownEditor.svelte');

		expect(source).toContain('<h2>Welcome to sideBar</h2>');
		expect(source).not.toContain('MARKETING_COPY.tagline');
		expect(source).not.toContain('MARKETING_COPY.subtitle');
		expect(source).not.toContain('Select a note, website, or file to get started');
	});
});
