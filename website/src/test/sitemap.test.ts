import { describe, expect, it } from 'vitest';
import { GET } from '../routes/sitemap.xml/+server';

describe('sitemap', () => {
  it('includes pricing and omits lastmod tags', async () => {
    const response = await GET({} as never);
    const xml = await response.text();

    expect(xml).toContain('<loc>https://trysidebar.ai/early-access/</loc>');
    expect(xml).toContain('<loc>https://trysidebar.ai/pricing/</loc>');
    expect(xml).not.toContain('<lastmod>');
  });
});
