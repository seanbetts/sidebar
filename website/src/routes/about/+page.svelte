<script lang="ts">
  import Seo from '$lib/components/Seo.svelte';

  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'AboutPage',
    name: 'About sideBar',
    url: 'https://trysidebar.ai/about',
    description: 'The story behind sideBar — why it was built and where it is going.'
  };
</script>

<Seo
  title="About"
  description="The story behind sideBar — why it was built and where it is going."
  url="https://trysidebar.ai/about"
  {jsonLd}
/>

<div class="page">
  <div class="page-inner">
    <!-- Header -->
    <header class="page-header">
      <h1>About sideBar</h1>
      <p class="lead">
        sideBar is an AI assistant built around how you actually work — not how an AI
        company thinks you should.
      </p>
    </header>

    <!-- Story -->
    <section class="story" aria-labelledby="story-heading">
      <h2 id="story-heading">The story</h2>
      <p>
        Most AI tools are designed to replace how you work. sideBar is built to work
        alongside you instead. It lives where your content lives — your notes, tasks,
        saved articles, and files — and an AI that can read all of it and help you get
        things done without making you switch contexts or copy things around.
      </p>
      <p>
        The core idea is that your assistant should know you. Not in a surveillance
        sense, but in the way a good colleague knows your preferences, your priorities,
        and your working style. sideBar builds that understanding over time and uses it
        in every conversation.
      </p>
      <p>
        We are building this in the open, learning as we go, and shipping updates
        constantly. If you have feedback, we want to hear it.
      </p>
    </section>

    <!-- Contact -->
    <section class="contact" aria-labelledby="contact-heading">
      <h2 id="contact-heading">Get in touch</h2>
      <p>
        For support, feature requests, or anything else, email us at
        <a href="mailto:support@trysidebar.ai">support@trysidebar.ai</a>.
        You can also find the full documentation at
        <a href="https://docs.trysidebar.ai" target="_blank" rel="noopener noreferrer">docs.trysidebar.ai</a>.
      </p>
    </section>
  </div>
</div>

<style>
  .page {
    padding: 5rem 1.5rem;
  }

  .page-inner {
    max-width: 48rem;
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: 3rem;
  }

  .page-header h1 {
    margin: 0 0 1rem;
    font-size: clamp(2rem, 4vw, 2.75rem);
    font-weight: 700;
    letter-spacing: -0.02em;
  }

  .lead {
    margin: 0;
    font-size: 1.175rem;
    line-height: 1.6;
    color: var(--color-muted-foreground);
  }

  .story h2,
  .contact h2 {
    margin: 0 0 1rem;
    font-size: 1.25rem;
    font-weight: 600;
    letter-spacing: -0.01em;
  }

  .story p,
  .contact p {
    margin: 0 0 1rem;
    font-size: 1rem;
    line-height: 1.7;
    color: var(--color-muted-foreground);
  }

  .story p:last-child,
  .contact p:last-child {
    margin-bottom: 0;
  }

  a {
    color: var(--color-foreground);
    text-decoration: underline;
    text-underline-offset: 3px;
  }

  a:hover {
    color: var(--color-muted-foreground);
  }
</style>
