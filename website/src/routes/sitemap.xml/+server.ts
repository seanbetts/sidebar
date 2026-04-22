import type { RequestHandler } from './$types';

export const prerender = true;

const SITE_URL = 'https://trysidebar.ai';

const pages = [
  { path: '/', priority: '1.0', changefreq: 'weekly' },
  { path: '/about/', priority: '0.8', changefreq: 'monthly' },
  { path: '/early-access/', priority: '0.85', changefreq: 'weekly' },
  { path: '/pricing/', priority: '0.7', changefreq: 'monthly' },
  { path: '/privacy/', priority: '0.5', changefreq: 'monthly' }
];

export const GET: RequestHandler = () => {
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${pages
  .map(
    ({ path, priority, changefreq }) => `  <url>
    <loc>${SITE_URL}${path}</loc>
    <changefreq>${changefreq}</changefreq>
    <priority>${priority}</priority>
  </url>`
  )
  .join('\n')}
</urlset>`;

  return new Response(xml, {
    headers: {
      'Content-Type': 'application/xml'
    }
  });
};
