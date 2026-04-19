<script lang="ts">
  interface Props {
    title: string;
    description: string;
    image?: string;
    url?: string;
    type?: 'website' | 'article';
    jsonLd?: Record<string, unknown> | Record<string, unknown>[];
  }

  let {
    title,
    description,
    image = 'https://trysidebar.ai/og-image.png',
    url = 'https://trysidebar.ai',
    type = 'website',
    jsonLd
  }: Props = $props();

  const fullTitle = $derived(title === 'sideBar' ? title : `${title} — sideBar`);
  const jsonLdString = $derived(
    jsonLd ? JSON.stringify(Array.isArray(jsonLd) ? jsonLd : [jsonLd]).replace(/<\//g, '<\\/') : null
  );
</script>

<svelte:head>
  <title>{fullTitle}</title>
  <meta name="description" content={description} />

  <!-- OpenGraph -->
  <meta property="og:title" content={fullTitle} />
  <meta property="og:description" content={description} />
  <meta property="og:image" content={image} />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />
  <meta property="og:url" content={url} />
  <meta property="og:type" content={type} />
  <meta property="og:site_name" content="sideBar" />

  <!-- Twitter / X -->
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content={fullTitle} />
  <meta name="twitter:description" content={description} />
  <meta name="twitter:image" content={image} />

  <!-- Canonical -->
  <link rel="canonical" href={url} />

  <!-- JSON-LD structured data -->
  {#if jsonLdString}
    {@html `<script type="application/ld+json">${jsonLdString}<\/script>`}
  {/if}
</svelte:head>
