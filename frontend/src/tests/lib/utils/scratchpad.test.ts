import { describe, expect, it } from 'vitest';
import { stripHeading, withHeading } from '$lib/utils/scratchpad';

describe('scratchpad utils', () => {
	it('strips the canonical scratchpad title from plain text content', () => {
		expect(stripHeading('✏️ Scratchpad\n\nHello\n')).toBe('Hello');
	});

	it('preserves other content when the title is absent', () => {
		expect(stripHeading('# Notes\n\nHello')).toBe('# Notes\n\nHello');
	});

	it('wraps body content with the scratchpad heading', () => {
		expect(withHeading('Hello')).toBe('# ✏️ Scratchpad\n\nHello\n');
	});
});
