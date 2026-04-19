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

    expect(css).toMatch(/font-family:\s*'SF Pro Text',\s*'SF Pro Display',\s*-apple-system/i);
    expect(css).not.toMatch(/@font-face/i);
  });
});
