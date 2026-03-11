<script lang="ts">
  import Seo from '$lib/components/Seo.svelte';

  const screenshots = [
    {
      src: '/screenshots/overview.png',
      alt: 'sideBar on iPad showing the chat panel open alongside a website summary',
      label: 'Chat'
    },
    {
      src: '/screenshots/notes.png',
      alt: 'sideBar notes with folders and a product roadmap note open',
      label: 'Notes'
    },
    {
      src: '/screenshots/tasks.png',
      alt: 'sideBar tasks showing the Today view with grouped tasks across projects',
      label: 'Tasks'
    },
    {
      src: '/screenshots/websites.png',
      alt: 'sideBar websites showing a saved article open with the full text extracted',
      label: 'Websites'
    },
    {
      src: '/screenshots/files.png',
      alt: 'sideBar files list showing uploaded documents, images, and other file types',
      label: 'Files'
    },
    {
      src: '/screenshots/skills-store.png',
      alt: 'sideBar Skills Store showing installable skills including Audio Transcription, YouTube, and more',
      label: 'Skills Store'
    }
  ];

  let activeIndex = $state(0);

  function prev() {
    activeIndex = (activeIndex - 1 + screenshots.length) % screenshots.length;
  }

  function next() {
    activeIndex = (activeIndex + 1) % screenshots.length;
  }

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
      title: 'Skills',
      description:
        'Extend sideBar with installable skills. Transcribe audio, save YouTube videos, analyse websites, and more — browse the Skills Store and add what you need.'
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
      title: 'Websites',
      description:
        'Save web pages to read offline. sideBar extracts the full content, indexes it, and makes it available to reference in any conversation.'
    },
    {
      title: 'Files',
      description:
        'Upload PDFs, documents, spreadsheets, images, and more. sideBar processes and indexes everything so you can search and ask questions about it all.'
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
    <div class="carousel">
      <!-- Main image -->
      <div class="carousel-stage">
        <img
          src={screenshots[activeIndex].src}
          alt={screenshots[activeIndex].alt}
          width="1366"
          height="1024"
        />
        <button class="carousel-btn carousel-prev" onclick={prev} aria-label="Previous screenshot">
          ‹
        </button>
        <button class="carousel-btn carousel-next" onclick={next} aria-label="Next screenshot">
          ›
        </button>
      </div>
      <!-- Thumbnails -->
      <div class="carousel-thumbs" role="tablist" aria-label="Screenshot thumbnails">
        {#each screenshots as shot, i}
          <button
            class="thumb"
            class:active={i === activeIndex}
            onclick={() => (activeIndex = i)}
            role="tab"
            aria-selected={i === activeIndex}
            aria-label={`View screenshot ${i + 1}`}
          >
              <img src={shot.src} alt={shot.alt} width="1366" height="1024" />
            <span class="thumb-label">{shot.label}</span>
          </button>
        {/each}
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
    grid-template-columns: repeat(3, 1fr);
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

  .carousel {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  /* Main stage */
  .carousel-stage {
    position: relative;
    border-radius: 0.75rem;
    overflow: hidden;
    border: 1px solid var(--color-border);
  }

  .carousel-stage img {
    display: block;
    width: 100%;
    height: auto;
  }

  .carousel-btn {
    position: absolute;
    top: 50%;
    transform: translateY(-50%);
    width: 2.5rem;
    height: 2.5rem;
    border-radius: 999px;
    border: 1px solid var(--color-border);
    background: color-mix(in oklch, var(--color-background) 80%, transparent);
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
    color: var(--color-foreground);
    font-size: 1.5rem;
    line-height: 1;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: background 0.15s;
  }

  .carousel-btn:hover {
    background: var(--color-background);
  }

  .carousel-prev {
    left: 0.75rem;
  }

  .carousel-next {
    right: 0.75rem;
  }

  /* Thumbnails */
  .carousel-thumbs {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
    gap: 0.5rem;
  }

  .thumb {
    padding: 0;
    border-radius: 0.5rem;
    overflow: hidden;
    border: 2px solid transparent;
    cursor: pointer;
    background: none;
    transition: border-color 0.15s;
  }

  .thumb img {
    display: block;
    width: 100%;
    height: auto;
    opacity: 0.55;
    transition: opacity 0.15s;
  }

  .thumb:hover img {
    opacity: 0.8;
  }

  .thumb.active {
    border-color: var(--color-foreground);
  }

  .thumb.active img {
    opacity: 1;
  }

  .thumb-label {
    display: block;
    text-align: center;
    font-size: 0.75rem;
    font-weight: 500;
    color: var(--color-muted-foreground);
    padding: 0.35rem 0 0.1rem;
    transition: color 0.15s;
  }

  .thumb.active .thumb-label {
    color: var(--color-foreground);
  }

  @media (max-width: 640px) {
    .features-grid {
      grid-template-columns: 1fr;
    }
  }

  @media (max-width: 480px) {
    .carousel-thumbs {
      grid-template-columns: repeat(auto-fit, minmax(5rem, 1fr));
      gap: 0.25rem;
    }

    .carousel-btn {
      width: 2rem;
      height: 2rem;
      font-size: 1.25rem;
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
