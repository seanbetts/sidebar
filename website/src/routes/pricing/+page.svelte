<script lang="ts">
  import Seo from '$lib/components/Seo.svelte';
  import PricingTierCard from '$lib/components/marketing/PricingTierCard.svelte';

  type BillingPeriod = 'monthly' | 'annual';

  let billingPeriod = $state<BillingPeriod>('monthly');

  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'WebPage',
    name: 'Pricing',
    url: 'https://trysidebar.ai/pricing',
    description:
      'sideBar pricing will include Free, Plus, Pro, and BYOK tiers. Final numbers are not published yet.'
  };

  const tierDefinitions = [
    {
      name: 'Free',
      monthlyPrice: '£0',
      annualPrice: '£0',
      subtitle: 'Try it free',
      summary: 'Use the core app features without the assistant.',
      bullets: [
        'Save websites, keep notes, and manage tasks in one place.',
        'Try the app structure and workflow before paying.',
        'Upgrade later if you want assistant access.'
      ]
    },
    {
      name: 'BYOK',
      monthlyPrice: '£5/mo',
      annualPrice: '£50/yr',
      subtitle: 'Bring your own key',
      summary: 'For people who want model usage billed directly by the provider.',
      bullets: [
        'Use your own Anthropic, OpenAI, or Google key.',
        'Keep subscription cost and model cost separate.',
        'Useful if you already have model access in place.'
      ]
    },
    {
      name: 'Plus',
      status: 'Coming soon',
      monthlyPrice: '£8/mo',
      annualPrice: '£80/yr',
      subtitle: 'Everyday use',
      summary: 'For regular use once sideBar becomes part of your weekly flow.',
      bullets: [
        'Built for people who use sideBar often.',
        'More room than Free for ongoing work.',
        'A simple subscription for everyday use.'
      ]
    },
    {
      name: 'Pro',
      status: 'Coming soon',
      monthlyPrice: '£15/mo',
      annualPrice: '£150/yr',
      subtitle: 'Pro use',
      summary: 'For people who rely on sideBar throughout the day.',
      bullets: [
        'Designed for heavier daily workflows.',
        'More capacity than Plus for active use.',
        'The strongest subscription tier when sideBar becomes essential.'
      ]
    }
  ];

  const tiers = $derived(
    tierDefinitions.map((tier) => ({
      ...tier,
      price: billingPeriod === 'annual' ? tier.annualPrice : tier.monthlyPrice
    }))
  );
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
        Free gives you the core app features without the assistant. BYOK is for
        people who want full access while model usage is billed directly by
        Anthropic, OpenAI, or Google. Plus and Pro are the bundled subscription
        tiers for more frequent use and higher limits.
      </p>

      <div class="billing-toggle" role="group" aria-label="Billing period">
        <button
          type="button"
          class:selected={billingPeriod === 'monthly'}
          aria-pressed={billingPeriod === 'monthly'}
          onclick={() => {
            billingPeriod = 'monthly';
          }}
        >
          Monthly
        </button>
        <button
          type="button"
          class:selected={billingPeriod === 'annual'}
          aria-pressed={billingPeriod === 'annual'}
          onclick={() => {
            billingPeriod = 'annual';
          }}
        >
          Annual
        </button>
      </div>
    </div>
  </section>

  <section class="tiers-section" aria-label="Pricing tiers">
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
    --page-display-size: clamp(2.25rem, 4.8vw, 4.5rem);
    --page-body-leading: 1.7;
    --page-copy-max: 42rem;
    padding: clamp(2.75rem, 6vw, 5rem) 0 0;
  }

  .intro,
  .tiers-section {
    position: relative;
  }

  .intro {
    padding-bottom: clamp(2rem, 4vw, 2.75rem);
  }

  .tiers-section {
    padding: 0 0 clamp(3.25rem, 7vw, 5rem);
  }

  .page-shell {
    margin: 0 auto;
    padding: 0 var(--page-gutter);
  }

  .page-shell--wide {
    max-width: var(--page-width);
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
  p {
    margin: 0;
  }

  h1 {
    color: var(--color-foreground);
  }

  h1 {
    font-size: var(--page-display-size);
    font-weight: var(--font-display-weight);
    line-height: var(--font-display-leading);
    letter-spacing: var(--font-display-tracking);
    text-wrap: balance;
  }

  .lead {
    margin-top: 1rem;
    max-width: var(--page-copy-max);
    font-size: var(--page-body-size);
    line-height: var(--page-body-leading);
    color: var(--color-muted-foreground);
  }

  .billing-toggle {
    display: inline-flex;
    gap: 0.375rem;
    margin-top: 1.5rem;
    padding: 0.25rem;
    border: 1px solid var(--color-border);
    border-radius: 999px;
    background: var(--color-card);
  }

  .billing-toggle button {
    border: 0;
    background: transparent;
    color: var(--color-muted-foreground);
    font: inherit;
    font-size: 0.95rem;
    font-weight: 600;
    line-height: 1;
    padding: 0.65rem 1rem;
    border-radius: 999px;
    cursor: pointer;
    transition:
      background-color 0.15s ease,
      color 0.15s ease;
  }

  .billing-toggle button.selected {
    background: var(--color-foreground);
    color: var(--color-background);
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
