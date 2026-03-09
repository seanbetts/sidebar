import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const projectRoot = process.cwd();
const rootHeadersPath = resolve(projectRoot, '_headers');
const staticHeadersPath = resolve(projectRoot, 'static/_headers');

describe('Cloudflare adapter project layout', () => {
	it('keeps custom headers in the frontend project root', () => {
		expect(existsSync(rootHeadersPath)).toBe(true);

		const headers = readFileSync(rootHeadersPath, 'utf8');

		expect(headers).toContain('/.well-known/apple-app-site-association');
		expect(headers).toContain('/apple-app-site-association');
	});

	it('does not keep a _headers file in static assets', () => {
		expect(existsSync(staticHeadersPath)).toBe(false);
	});
});
