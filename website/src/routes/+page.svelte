<script lang="ts">
  import Seo from '$lib/components/Seo.svelte';
  import DeviceShowcase from '$lib/components/marketing/DeviceShowcase.svelte';
  import ProofSection from '$lib/components/marketing/ProofSection.svelte';
  import { siteCopy } from '$lib/content/siteCopy';
  import { MARKETING_COPY } from '../../../shared/marketingCopy';

  const { hero, thesis, proofs, identity, close } = siteCopy.home;

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
        <p class="eyebrow">{hero.eyebrow}</p>
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

  <section class="thesis" aria-labelledby="thesis-heading">
    <div class="thesis-inner">
      <h2 id="thesis-heading" class="thesis-heading">{thesis.heading}</h2>
      <p class="thesis-body">{thesis.body}</p>
    </div>
  </section>

  <section class="proofs" aria-label="Workflow proof sequence">
    {#each proofs as proof, index (proof.heading)}
      <ProofSection {...proof} reverse={index % 2 === 1} />
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
        <DeviceShowcase media={identity.media} chrome="bare" />
      </div>
    </div>
  </section>

  <section class="campaign-close" aria-labelledby="campaign-close-heading">
    <div class="close-inner">
      <h2 id="campaign-close-heading">{close.headline}</h2>
      <p>{close.body}</p>

      <div class="cta-row close-actions">
        <a class="action action-primary" href={close.primaryHref}>{close.primaryCta}</a>
      </div>
    </div>
  </section>
</div>

<style>
  .home {
    --marketing-device-ipad-width: 40rem;
    --marketing-device-iphone-width: 20rem;
    padding-bottom: clamp(4rem, 8vw, 6rem);
  }

  .hero {
    padding: clamp(2.5rem, 6vw, 5rem) 0 clamp(4rem, 7vw, 6rem);
    border-bottom: 1px solid var(--color-border);
  }

  .hero-inner {
    max-width: 78rem;
    margin: 0 auto;
    padding: 0 1.5rem;
    display: grid;
    grid-template-columns: minmax(0, 0.82fr) minmax(0, 1.18fr);
    gap: clamp(2rem, 5vw, 4rem);
    align-items: center;
  }

  .hero-copy {
    display: grid;
    gap: 1rem;
    max-width: 30rem;
  }

  .eyebrow,
  .hero-subhead,
  .hero-platforms,
  .thesis-body,
  .identity-copy p,
  .close-inner p {
    margin: 0;
    color: var(--color-muted-foreground);
  }

  .eyebrow {
    font-size: 0.78rem;
    font-weight: 600;
    letter-spacing: 0.16em;
    text-transform: uppercase;
  }

  .hero-title,
  .thesis-heading,
  .identity-copy h2,
  .close-inner h2 {
    margin: 0;
    color: var(--color-foreground);
  }

  .hero-title {
    font-size: clamp(3rem, 8vw, 5.75rem);
    line-height: 0.92;
    letter-spacing: -0.065em;
    text-wrap: balance;
  }

  .hero-subhead {
    font-size: clamp(1rem, 2vw, 1.18rem);
    line-height: 1.75;
    max-width: 31rem;
  }

  .hero-platforms {
    font-size: 0.9rem;
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
    transition: transform 0.2s ease;
  }

  .hero-poster {
    justify-self: end;
  }

  .thesis {
    padding: clamp(4rem, 8vw, 6rem) 0;
  }

  .thesis-inner {
    max-width: 58rem;
    margin: 0 auto;
    padding: 0 1.5rem;
    display: grid;
    gap: 1.5rem;
  }

  .thesis-heading,
  .identity-copy h2,
  .close-inner h2 {
    font-size: clamp(2.35rem, 6vw, 4.4rem);
    line-height: 0.95;
    letter-spacing: -0.06em;
    text-wrap: balance;
  }

  .thesis-heading {
    max-width: 13ch;
  }

  .thesis-body,
  .identity-copy p,
  .close-inner p {
    max-width: 45rem;
    font-size: clamp(1.04rem, 2vw, 1.28rem);
    line-height: 1.8;
  }

  .identity {
    padding: clamp(3.5rem, 8vw, 5.5rem) 0;
    border-top: 1px solid var(--color-border);
    background: var(--surface);
  }

  .identity-inner {
    max-width: 78rem;
    margin: 0 auto;
    padding: 0 1.5rem;
    display: grid;
    grid-template-columns:
      minmax(0, 1fr)
      minmax(18rem, var(--marketing-device-ipad-width));
    gap: clamp(1.75rem, 5vw, 4rem);
    align-items: start;
  }

  .identity-copy {
    display: grid;
    gap: 1rem;
    max-width: 31rem;
  }

  .identity-points {
    margin: 0.5rem 0 0;
    padding: 0;
    list-style: none;
    display: grid;
    gap: 0.85rem;
  }

  .identity-points li {
    padding-top: 0.85rem;
    border-top: 1px solid var(--color-border);
    color: var(--color-muted-foreground);
    line-height: 1.7;
  }

  .identity-media {
    justify-self: end;
  }

  .campaign-close {
    padding: clamp(4rem, 8vw, 6rem) 0 0;
    border-top: 1px solid var(--color-border);
  }

  .close-inner {
    max-width: 60rem;
    margin: 0 auto;
    padding: 0 1.5rem;
    display: grid;
    gap: 1.25rem;
    text-align: center;
  }

  .close-inner h2,
  .close-inner p {
    justify-self: center;
  }

  .close-actions {
    justify-content: center;
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
      justify-self: start;
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
    .thesis-inner,
    .identity-inner,
    .close-inner {
      padding: 0 1rem;
    }

    .hero-title {
      font-size: clamp(2.65rem, 15vw, 4.2rem);
    }

    .thesis-heading,
    .identity-copy h2,
    .close-inner h2 {
      font-size: clamp(2.2rem, 12vw, 3.25rem);
    }

    .cta-row {
      width: 100%;
    }

    .action {
      flex: 1 1 12rem;
    }
  }
</style>
