<script lang="ts">
  import Seo from '$lib/components/Seo.svelte';

  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'WebPage',
    name: 'Pricing',
    url: 'https://trysidebar.ai/pricing',
    description: 'Pricing information for sideBar is coming soon.'
  };
</script>

<Seo title="Pricing" description="Pricing information for sideBar is coming soon." url="https://trysidebar.ai/pricing" {jsonLd} />

<div class="page">
  <div class="page-inner">
    <h1>Pricing</h1>
    <p>Pricing information is being prepared.</p>
  </div>
</div>
