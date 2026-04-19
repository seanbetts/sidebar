<script lang="ts">
  import PixelDivider from '$lib/components/PixelDivider.svelte';
  import Seo from '$lib/components/Seo.svelte';
  import PricingTierCard from '$lib/components/marketing/PricingTierCard.svelte';

  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'WebPage',
    name: 'Pricing',
    url: 'https://trysidebar.ai/pricing',
    description:
      'sideBar pricing will include Free, Plus, Pro, and BYOK tiers. Final numbers are not published yet.'
  };

  const tiers = [
    {
      name: 'Free',
      price: 'Try it free',
      summary: 'A no-commitment way to try the assistant and work environment together.',
      bullets: [
        'Start with the core sideBar workflows.',
        'See how the product fits into your day before paying.',
        'Upgrade later if it becomes part of your routine.'
      ]
    },
    {
      name: 'Plus',
      price: 'Coming later',
      summary: 'For regular use once sideBar becomes part of your weekly flow.',
      bullets: [
        'Built for people who use sideBar often.',
        'More room than Free for ongoing work.',
        'A simple subscription for everyday use.'
      ]
    },
    {
      name: 'Pro',
      price: 'Coming later',
      summary: 'For people who rely on sideBar throughout the day.',
      bullets: [
        'Designed for heavier daily workflows.',
        'More capacity than Plus for active use.',
        'The strongest subscription tier when sideBar becomes essential.'
      ]
    },
    {
      name: 'BYOK',
      price: 'Bring your own key',
      summary: 'For people who want model usage billed directly by the provider.',
      bullets: [
        'Use your own Anthropic, OpenAI, or Google key.',
        'Keep subscription cost and model cost separate.',
        'Useful if you already have model access in place.'
      ]
    }
  ];
</script>

<Seo
  title="Pricing"
  description="sideBar pricing will include Free, Plus, Pro, and BYOK tiers. Final numbers are not published yet."
  url="https://trysidebar.ai/pricing"
  {jsonLd}
/>

<div class="page">
  <section class="intro">
    <div class="page-shell page-shell--wide">
      <p class="eyebrow">Plans</p>
      <h1>Pricing</h1>
      <p class="lead">
        sideBar will have a free entry point, paid plans for heavier use, and a
        BYOK option for people who want model costs billed separately. The plan is
        public now, even though the final numbers are not.
      </p>
    </div>
  </section>

  <section class="model-section">
    <PixelDivider position="top" />
    <div class="page-shell page-shell--narrow prose-block">
      <h2 id="pricing-model-heading">How the model works</h2>
      <p>
        Free is for trying the core workflow. Plus and Pro are the subscription tiers
        for more frequent use and higher limits. BYOK lets people bring their own
        Anthropic, OpenAI, or Google key and pay model providers directly.
      </p>
      <p>
        The structure is clear now so people can understand the model before the
        final numbers are published.
      </p>
    </div>
  </section>

  <section class="tiers-section" aria-label="Pricing tiers">
    <PixelDivider position="top" />
    <div class="page-shell page-shell--wide">
      <ul class="tiers-grid" aria-label="Pricing tiers">
        {#each tiers as tier}
          <li>
            <PricingTierCard {...tier} />
          </li>
        {/each}
      </ul>
    </div>
  </section>
</div>

<style>
  .page {
    --page-width: 78rem;
    --page-width-narrow: 48rem;
    --page-gutter: 1.5rem;
    --page-body-size: clamp(1.02rem, 1vw + 0.82rem, 1.125rem);
    --page-heading-size: clamp(2.35rem, 4vw + 1.2rem, 3.75rem);
    --page-display-size: clamp(3rem, 6vw, 4.8rem);
    --page-body-leading: 1.7;
    --page-heading-leading: 0.98;
    --page-copy-max: 42rem;
    padding: clamp(2.75rem, 6vw, 5rem) 0 0;
  }

  .intro,
  .model-section,
  .tiers-section {
    position: relative;
  }

  .intro {
    padding-bottom: clamp(3rem, 6vw, 4.5rem);
  }

  .model-section,
  .tiers-section {
    padding: clamp(3.25rem, 7vw, 5rem) 0;
  }

  .page-shell {
    margin: 0 auto;
    padding: 0 var(--page-gutter);
  }

  .page-shell--wide {
    max-width: var(--page-width);
  }

  .page-shell--narrow {
    max-width: var(--page-width-narrow);
  }

  .eyebrow {
    margin: 0 0 0.75rem;
    font-size: 0.78rem;
    font-weight: 600;
    letter-spacing: 0.16em;
    text-transform: uppercase;
    color: var(--color-muted-foreground);
  }

  h1,
  h2,
  p {
    margin: 0;
  }

  h1,
  h2 {
    color: var(--color-foreground);
  }

  h1 {
    font-size: var(--page-display-size);
    line-height: 0.94;
    letter-spacing: -0.06em;
    text-wrap: balance;
  }

  .lead {
    margin-top: 1rem;
    max-width: var(--page-copy-max);
    font-size: var(--page-body-size);
    line-height: var(--page-body-leading);
    color: var(--color-muted-foreground);
  }

  .prose-block {
    display: grid;
    gap: 1rem;
  }

  h2 {
    font-size: var(--page-heading-size);
    line-height: var(--page-heading-leading);
    letter-spacing: -0.05em;
    text-wrap: balance;
  }

  .prose-block p {
    font-size: var(--page-body-size);
    line-height: var(--page-body-leading);
    color: var(--color-muted-foreground);
  }

  .tiers-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 1rem;
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .tiers-grid > li {
    min-width: 0;
  }

  @media (max-width: 48rem) {
    .tiers-grid {
      grid-template-columns: 1fr;
    }
  }

  @media (max-width: 640px) {
    .page {
      --page-gutter: 1rem;
    }
  }
</style>
