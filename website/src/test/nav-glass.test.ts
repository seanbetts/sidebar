declare global {
  interface ImportMeta {
    dirname: string;
  }
}

import { describe, expect, it } from 'vitest';
// @ts-ignore - website tsconfig does not include Node types, but Vitest runs this test in Node.
import { readFileSync } from 'node:fs';

describe('website nav glass styling', () => {
  it('defines translucent glass tokens for light and dark themes', () => {
    const css = readFileSync(`${import.meta.dirname}/../app.css`, 'utf8');

    expect(css).toMatch(/--surface-glass:\s*oklch\([^)]+\/\s*0\.[0-9]+\)/i);
    expect(css).toMatch(/--surface-glass-fallback:\s*oklch\([^)]+\/\s*0\.[0-9]+\)/i);
    expect(css).toMatch(/--glass-stroke:\s*oklch\([^)]+\/\s*0\.[0-9]+\)/i);
  });

  it('uses backdrop blur on the sticky navbar with a solid fallback', () => {
    const navSource = readFileSync(`${import.meta.dirname}/../lib/components/Nav.svelte`, 'utf8');

    expect(navSource).toMatch(/position:\s*sticky/i);
    expect(navSource).toMatch(/background:\s*var\(--surface-glass-fallback\)/i);
    expect(navSource).toMatch(/-webkit-backdrop-filter:\s*saturate\(180%\)\s*blur\(1\.5rem\)/i);
    expect(navSource).toMatch(/backdrop-filter:\s*saturate\(180%\)\s*blur\(1\.5rem\)/i);
    expect(navSource).toMatch(/@supports\s*\(\(-webkit-backdrop-filter:\s*blur\(1px\)\)\s*or\s*\(backdrop-filter:\s*blur\(1px\)\)\)/i);
  });
});
