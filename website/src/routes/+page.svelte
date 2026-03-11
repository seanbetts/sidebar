<script lang="ts">
  import Seo from '$lib/components/Seo.svelte';

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
    description:
      'An AI assistant for iPhone, iPad, and Mac. Take notes, manage tasks, save websites, and work with files — all with AI that learns how you work.',
    operatingSystem: 'iOS, iPadOS, macOS',
    applicationCategory: 'ProductivityApplication',
    offers: {
      '@type': 'Offer',
      price: '0',
      priceCurrency: 'USD'
    },
    url: 'https://trysidebar.ai'
  };

  const features = [
    {
      title: 'Chat',
      description:
        'Ask questions, get things done, and work through problems with an AI that knows your content and adapts to how you think.'
    },
    {
      title: 'Notes',
      description:
        'A full writing environment with folders, rich text, and a Scratchpad always one tap away. sideBar can read and reference everything you write.'
    },
    {
      title: 'Tasks',
      description:
        'Create and manage to-dos manually or just ask sideBar to do it. Smart lists surface what matters today, this week, and upcoming.'
    },
    {
      title: 'Websites and Files',
      description:
        'Save web pages to read offline and upload documents. sideBar indexes everything so you can search, summarise, and ask questions about it all.'
    }
  ];
</script>

<Seo
  title="sideBar"
  description="An AI assistant for iPhone, iPad, and Mac. Take notes, manage tasks, save websites, and work with files — all with AI that learns how you work."
  url="https://trysidebar.ai"
  jsonLd={[organizationJsonLd, appJsonLd]}
/>

<!-- Hero -->
<section class="hero">
  <div class="hero-inner">
    <div class="hero-logo">
      <img class="logo-light" src="/logo-animated-light.gif" alt="sideBar" width="96" height="96" />
      <img class="logo-dark" src="/logo-animated-dark.gif" alt="" aria-hidden="true" width="96" height="96" />
    </div>
    <h1 class="hero-title">Your AI assistant,<br />built around how you work</h1>
    <p class="hero-subtitle">
      Take notes, manage tasks, save websites, and work with files — with an AI that
      reads your content, remembers your preferences, and gets things done alongside you.
    </p>
    <a href="https://app.trysidebar.ai" class="hero-cta">Request Early Access</a>
    <p class="hero-platforms">Available on iPhone, iPad, Mac, and web</p>
  </div>
</section>

<!-- Features -->
<section class="features" aria-labelledby="features-heading">
  <div class="section-inner">
    <h2 id="features-heading" class="section-title">Everything in one place</h2>
    <p class="section-subtitle">
      sideBar brings together the tools you already use with an AI that can see
      all of it and help you do more.
    </p>
    <div class="features-grid">
      {#each features as feature (feature.title)}
        <article class="feature-card">
          <h3 class="feature-title">{feature.title}</h3>
          <p class="feature-description">{feature.description}</p>
        </article>
      {/each}
    </div>
  </div>
</section>

<!-- Screenshots -->
<section class="screenshots" aria-labelledby="screenshots-heading">
  <div class="section-inner">
    <h2 id="screenshots-heading" class="section-title">See it in action</h2>
    <div class="screenshot-grid">
      <img
        class="screenshot-primary"
        src="/screenshots/overview.png"
        alt="sideBar on iPad showing the chat panel open alongside a website summary"
        width="1366"
        height="1024"
      />
      <div class="screenshot-row">
        <img
          src="/screenshots/notes.png"
          alt="sideBar notes with folders and a product roadmap note open"
          width="1366"
          height="1024"
        />
        <img
          src="/screenshots/tasks.png"
          alt="sideBar tasks showing the Today view with grouped tasks across projects"
          width="1366"
          height="1024"
        />
        <img
          src="/screenshots/websites.png"
          alt="sideBar websites showing a saved article open with the full text extracted"
          width="1366"
          height="1024"
        />
      </div>
    </div>
  </div>
</section>

<!-- Bottom CTA -->
<section class="bottom-cta">
  <div class="section-inner">
    <h2>Ready to get started?</h2>
    <a href="https://app.trysidebar.ai" class="hero-cta">Request Early Access</a>
  </div>
</section>

<style>
  /* ---- Hero ---- */
  .hero {
    padding: 6rem 1.5rem 5rem;
    text-align: center;
    background:
      radial-gradient(circle at 15% 10%, oklch(0.7 0.1 250 / 0.1) 0, transparent 45%),
      radial-gradient(circle at 85% 20%, oklch(0.65 0.1 280 / 0.1) 0, transparent 40%);
  }

  .hero-inner {
    max-width: 52rem;
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 1.25rem;
  }

  .logo-light { display: block; }
  .logo-dark { display: none; }

  :global(.dark) .logo-light { display: none; }
  :global(.dark) .logo-dark { display: block; }

  .hero-title {
    margin: 0;
    font-size: clamp(2rem, 5vw, 3.25rem);
    font-weight: 700;
    line-height: 1.15;
    letter-spacing: -0.02em;
    color: var(--color-foreground);
  }

  .hero-subtitle {
    margin: 0;
    max-width: 38rem;
    font-size: clamp(1rem, 2vw, 1.175rem);
    line-height: 1.6;
    color: var(--color-muted-foreground);
  }

  .hero-cta {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 0.75rem 1.75rem;
    border-radius: 999px;
    border: 1px solid oklch(1 0 0 / 0.45);
    background: linear-gradient(180deg, oklch(1 0 0 / 0.2) 0, transparent 100%),
      var(--color-primary);
    color: var(--color-primary-foreground);
    font-size: 1rem;
    font-weight: 500;
    text-decoration: none;
    transition: opacity 0.15s;
  }

  .hero-cta:hover {
    opacity: 0.85;
  }

  .hero-platforms {
    margin: 0;
    font-size: 0.875rem;
    color: var(--color-muted-foreground);
  }

  /* ---- Shared section styles ---- */
  .section-inner {
    max-width: 72rem;
    margin: 0 auto;
    padding: 0 1.5rem;
  }

  .section-title {
    margin: 0 0 0.75rem;
    font-size: clamp(1.5rem, 3vw, 2rem);
    font-weight: 700;
    letter-spacing: -0.015em;
    text-align: center;
  }

  .section-subtitle {
    margin: 0 auto 3rem;
    max-width: 38rem;
    font-size: 1rem;
    line-height: 1.6;
    color: var(--color-muted-foreground);
    text-align: center;
  }

  /* ---- Features ---- */
  .features {
    padding: 5rem 0;
  }

  .features-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr));
    gap: 1.25rem;
  }

  .feature-card {
    padding: 1.5rem;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl, 1rem);
    background: var(--color-card);
  }

  .feature-title {
    margin: 0 0 0.5rem;
    font-size: 1rem;
    font-weight: 600;
    color: var(--color-card-foreground);
  }

  .feature-description {
    margin: 0;
    font-size: 0.875rem;
    line-height: 1.6;
    color: var(--color-muted-foreground);
  }

  /* ---- Screenshots ---- */
  .screenshots {
    padding: 5rem 0;
  }

  .screenshot-grid {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  .screenshot-grid img,
  .screenshot-row img {
    display: block;
    width: 100%;
    height: auto;
    border-radius: 0.75rem;
    border: 1px solid var(--color-border);
  }

  .screenshot-row {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 1rem;
  }

  @media (max-width: 640px) {
    .screenshot-row {
      grid-template-columns: 1fr;
    }
  }

  /* ---- Bottom CTA ---- */
  .bottom-cta {
    padding: 5rem 0;
    text-align: center;
  }

  .bottom-cta h2 {
    margin: 0 0 1.5rem;
    font-size: clamp(1.5rem, 3vw, 2rem);
    font-weight: 700;
    letter-spacing: -0.015em;
  }

  .bottom-cta .hero-cta {
    border-color: var(--color-border);
  }
</style>
