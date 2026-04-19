<script lang="ts">
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
  <div class="page-inner">
    <header class="page-header">
      <p class="eyebrow">Plans</p>
      <h1>Pricing</h1>
      <p class="lead">
        sideBar will have a free entry point, paid plans for heavier use, and a
        BYOK option for people who want model costs billed separately. The plan is
        public now, even though the final numbers are not.
      </p>
    </header>

    <section class="pricing-note" aria-labelledby="pricing-model-heading">
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
    </section>

    <section class="tiers" aria-label="Pricing tiers">
      <ul class="tiers-grid" aria-label="Pricing tiers">
        {#each tiers as tier}
          <li>
            <PricingTierCard {...tier} />
          </li>
        {/each}
      </ul>
    </section>
  </div>
</div>

<style>
  .page {
    padding: 5rem 0;
  }

  .page-inner {
    max-width: 72rem;
    margin: 0 auto;
    padding: 0 1.5rem;
    display: grid;
    gap: 2.5rem;
  }

  .page-header,
  .pricing-note,
  .tiers {
    display: grid;
    gap: 0.75rem;
    padding: 1.5rem;
    border: 1px solid var(--color-border);
    border-radius: calc(var(--radius) * 1.4);
    background: var(--card);
    box-shadow: 0 24px 60px -36px var(--shadow-color);
  }

  .eyebrow {
    margin: 0;
    font-size: 0.78rem;
    font-weight: 600;
    letter-spacing: 0.16em;
    text-transform: uppercase;
    color: var(--color-muted-foreground);
  }

  .lead {
    margin: 0;
    max-width: 46rem;
    font-size: 1.175rem;
    line-height: 1.6;
    color: var(--color-muted-foreground);
  }

  .pricing-note h2 {
    margin: 0;
    font-size: 1.25rem;
    font-weight: 600;
    letter-spacing: -0.01em;
  }

  .pricing-note p {
    margin: 0;
    font-size: 1rem;
    line-height: 1.7;
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
</style>
