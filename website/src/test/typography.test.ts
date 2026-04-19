declare global {
  interface ImportMeta {
    dirname: string;
  }
}

import { describe, expect, it } from 'vitest';
// @ts-ignore - website tsconfig does not include Node types, but Vitest runs this test in Node.
import { readFileSync } from 'node:fs';

describe('website typography', () => {
  it('keeps the site on a San Francisco-compatible system stack without hosted fonts', () => {
    const css = readFileSync(`${import.meta.dirname}/../app.css`, 'utf8');

    expect(css).toMatch(/--font-sans:\s*'SF Pro Text',\s*'SF Pro Display',\s*-apple-system/i);
    expect(css).toMatch(/--font-display:\s*'SF Pro Display',\s*'SF Pro Text',\s*-apple-system/i);
    expect(css).toMatch(/body\s*\{[\s\S]*font-family:\s*var\(--font-sans\)/i);
    expect(css).toMatch(/h1,\s*h2,\s*h3,\s*h4,\s*h5,\s*h6\s*\{[\s\S]*font-family:\s*var\(--font-display\)/i);
    expect(css).not.toMatch(/@font-face/i);
  });
});
