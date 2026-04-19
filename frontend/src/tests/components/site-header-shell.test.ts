import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

describe('site header shell styling', () => {
	it('removes the generic workspace subtitle and gradient treatment', () => {
		const source = readFileSync('src/lib/components/site-header.svelte', 'utf8');

		expect(source).not.toMatch(/Workspace/);
		expect(source).not.toMatch(/linear-gradient/);
	});
});
