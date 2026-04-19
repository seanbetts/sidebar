<script lang="ts">
  import Seo from '$lib/components/Seo.svelte';
  import DeviceShowcase from '$lib/components/marketing/DeviceShowcase.svelte';
  import ProofSection from '$lib/components/marketing/ProofSection.svelte';
  import { siteCopy } from '$lib/content/siteCopy';
  import { MARKETING_COPY } from '../../../shared/marketingCopy';

  const { hero, proofs, identity } = siteCopy.home;

  const organizationJsonLd = {
    '@context': 'https://schema.org',
    '@type': 'Organization',
    name: 'sideBar',
    url: 'https://trysidebar.ai',
    logo: 'https://trysidebar.ai/logo.svg',
    contactPoint: {
      '@type': 'ContactPoint',
      email: 'support@trysidebar.ai',
      contactType: 'customer support'
    }
  };

  const appJsonLd = {
    '@context': 'https://schema.org',
    '@type': 'MobileApplication',
    name: 'sideBar',
    description: MARKETING_COPY.description,
    operatingSystem: 'iOS, iPadOS, macOS',
    applicationCategory: 'ProductivityApplication',
    offers: {
      '@type': 'Offer',
      price: '0',
      priceCurrency: 'USD'
    },
    url: 'https://trysidebar.ai'
  };
</script>

<Seo
  title="sideBar"
  description={MARKETING_COPY.description}
  url="https://trysidebar.ai"
  jsonLd={[organizationJsonLd, appJsonLd]}
/>

<div class="home">
  <section class="hero">
    <div class="hero-inner">
      <div class="hero-copy">
        <h1 class="hero-title">{hero.headline}</h1>
        <p class="hero-subhead">{hero.subhead}</p>

        <div class="cta-row">
          <a class="action action-primary" href={hero.primaryHref}>{hero.primaryCta}</a>
          <a class="action action-secondary" href={hero.secondaryHref}>{hero.secondaryCta}</a>
        </div>

        <p class="hero-platforms">{hero.platforms}</p>
      </div>

      <div class="hero-poster">
        <DeviceShowcase media={hero.media} chrome="bare" />
      </div>
    </div>
  </section>

  <section class="proofs" aria-label="Workflow proof sequence">
    {#each proofs as proof (proof.heading)}
      <ProofSection {...proof} />
    {/each}
  </section>

  <section class="identity" aria-labelledby="identity-heading">
    <div class="identity-inner">
      <div class="identity-copy">
        <h2 id="identity-heading">{identity.heading}</h2>
        <p>{identity.body}</p>

        <ul class="identity-points" aria-label="sideBar identity proof points">
          {#each identity.points as point}
            <li>{point}</li>
          {/each}
        </ul>
      </div>

      <div class="identity-media">
        <DeviceShowcase
          media={identity.media}
          chrome={identity.media.kind === 'image' ? 'bare' : 'framed'}
        />
      </div>
    </div>
  </section>
</div>

<style>
  .home {
    --marketing-page-width: 78rem;
    --marketing-page-gutter: 1.5rem;
    --marketing-device-ipad-width: 40rem;
    --marketing-device-iphone-width: 22rem;
    --marketing-home-meta-size: 0.9375rem;
    --marketing-home-body-size: clamp(1.02rem, 1vw + 0.82rem, 1.125rem);
    --marketing-home-heading-size: clamp(2.4rem, 4vw + 1.4rem, 3.85rem);
    --marketing-home-display-size: clamp(3.35rem, 7vw, 5.2rem);
    --marketing-home-body-leading: 1.68;
    --marketing-home-heading-leading: 0.98;
    --marketing-home-display-leading: 0.94;
    --marketing-home-copy-max: 31rem;
  }

  .hero {
    padding: clamp(2.5rem, 6vw, 5rem) 0 clamp(4rem, 7vw, 6rem);
    border-bottom: 1px solid var(--color-border);
  }

  .hero-inner {
    max-width: var(--marketing-page-width);
    margin: 0 auto;
    padding: 0 var(--marketing-page-gutter);
    display: grid;
    grid-template-columns: minmax(0, 0.82fr) minmax(0, 1.18fr);
    gap: clamp(2rem, 5vw, 4rem);
    align-items: center;
  }

  .hero-copy {
    display: grid;
    gap: 1.125rem;
    max-width: var(--marketing-home-copy-max);
  }

  .hero-subhead,
  .hero-platforms,
  .identity-copy p {
    margin: 0;
    color: var(--color-muted-foreground);
  }

  .hero-title,
  .identity-copy h2 {
    margin: 0;
    color: var(--color-foreground);
  }

  .hero-title {
    font-size: var(--marketing-home-display-size);
    line-height: var(--marketing-home-display-leading);
    letter-spacing: -0.06em;
    text-wrap: balance;
    max-width: 11ch;
  }

  .hero-subhead {
    font-size: var(--marketing-home-body-size);
    line-height: var(--marketing-home-body-leading);
    max-width: var(--marketing-home-copy-max);
  }

  .hero-platforms {
    font-size: var(--marketing-home-meta-size);
  }

  .cta-row {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
    align-items: center;
  }

  .action {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-height: 3rem;
    padding: 0.75rem 1.25rem;
    border: 1px solid var(--color-border);
    border-radius: 999px;
    font-size: 0.95rem;
    font-weight: 600;
    white-space: nowrap;
    text-decoration: none;
    transition:
      background-color 0.15s ease,
      color 0.15s ease,
      border-color 0.15s ease,
      transform 0.15s ease;
  }

  .action-primary {
    background: var(--color-primary);
    border-color: var(--color-primary);
    color: var(--color-primary-foreground);
  }

  .action-primary:hover {
    background: var(--color-foreground);
    border-color: var(--color-foreground);
    color: var(--color-background);
  }

  .action-secondary {
    background: transparent;
    color: var(--color-foreground);
  }

  .action-secondary:hover {
    background: var(--color-secondary);
    border-color: var(--color-border);
  }

  .hero-poster,
  .identity-media {
    display: grid;
    width: 100%;
    align-items: center;
    justify-items: center;
    justify-self: center;
    transition: transform 0.2s ease;
  }

  .identity::before {
    content: '';
    position: absolute;
    top: 0;
    left: 50%;
    width: 100vw;
    border-top: 1px solid var(--color-border);
    transform: translateX(-50%);
  }

  .identity-copy h2 {
    font-size: var(--marketing-home-heading-size);
    line-height: var(--marketing-home-heading-leading);
    letter-spacing: -0.05em;
    text-wrap: balance;
  }

  .identity-copy p {
    max-width: 45rem;
    font-size: var(--marketing-home-body-size);
    line-height: var(--marketing-home-body-leading);
  }

  .identity {
    padding: clamp(3.5rem, 8vw, 5.5rem) 0;
    position: relative;
  }

  .identity-inner {
    max-width: var(--marketing-page-width);
    margin: 0 auto;
    padding: 0 var(--marketing-page-gutter);
    display: grid;
    grid-template-columns: minmax(0, 0.88fr) minmax(0, 1.12fr);
    gap: clamp(1.75rem, 5vw, 4rem);
    align-items: center;
  }

  .identity-copy {
    order: 2;
    display: grid;
    gap: 1.125rem;
    max-width: var(--marketing-home-copy-max);
  }

  .identity-points {
    margin: 0.375rem 0 0;
    padding: 0;
    list-style: none;
    display: grid;
    gap: 0.75rem;
  }

  .identity-points li {
    padding-top: 0.75rem;
    border-top: 1px solid var(--color-border);
    color: var(--color-muted-foreground);
    font-size: var(--marketing-home-body-size);
    line-height: 1.62;
  }

  .identity-media {
    order: 1;
  }
  @media (prefers-reduced-motion: no-preference) {
    .action:hover,
    .hero-poster:hover,
    .identity-media:hover {
      transform: translateY(-0.15rem);
    }
  }

  @media (max-width: 900px) {
    .hero-inner,
    .identity-inner {
      grid-template-columns: 1fr;
    }

    .hero-copy,
    .hero-poster,
    .identity-copy,
    .identity-media {
      max-width: none;
    }

    .identity-copy,
    .identity-media {
      order: initial;
    }

    .hero-poster {
      width: 100%;
    }

    .identity-media {
      width: 100%;
    }
  }

  @media (max-width: 640px) {
    .hero-inner,
    .identity-inner {
      padding: 0 1rem;
    }

    .hero-title {
      font-size: clamp(2.8rem, 14vw, 4rem);
    }

    .identity-copy h2 {
      font-size: clamp(2.15rem, 10vw, 3rem);
    }

    .cta-row {
      width: 100%;
    }

    .action {
      flex: 1 1 12rem;
    }
  }
</style>
