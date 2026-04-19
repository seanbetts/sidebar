// @ts-ignore - Node types are not included in the website tsconfig, but Vitest runs in Node.
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

describe('website typography', () => {
  it('keeps the site on a San Francisco-compatible system stack without hosted fonts', () => {
    const css = readFileSync('src/app.css', 'utf8');

    expect(css).toMatch(/font-family:\s*-apple-system,\s*BlinkMacSystemFont,\s*system-ui/i);
    expect(css).not.toMatch(/@font-face/i);
  });
});
