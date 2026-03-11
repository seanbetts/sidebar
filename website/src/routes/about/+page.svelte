<script lang="ts">
  import Seo from '$lib/components/Seo.svelte';

  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'AboutPage',
    name: 'About sideBar',
    url: 'https://trysidebar.ai/about',
    description:
      'sideBar is an AI assistant for iPhone, iPad, Mac, and web. It knows your notes, tasks, websites, and files, and brings that context into every conversation.'
  };
</script>

<Seo
  title="About"
  description="sideBar is an AI assistant for iPhone, iPad, Mac, and web. It knows your notes, tasks, websites, and files, and brings that context into every conversation."
  url="https://trysidebar.ai/about"
  {jsonLd}
/>

<div class="page">
  <div class="page-inner">
    <!-- Header -->
    <header class="page-header">
      <h1>About sideBar</h1>
      <p class="lead">
        An AI assistant for iPhone, iPad, Mac, and web that actually knows you.
        Your notes, tasks, saved websites, and files in one place, with an AI that
        can read all of it.
      </p>
    </header>
  </div>

  <!-- Hero image — wider than prose column -->
  <div class="hero-image">
    <img
      src="/screenshots/overview.png"
      alt="sideBar on iPad showing the chat panel open alongside a website summary"
      width="1366"
      height="1024"
    />
  </div>

  <div class="page-inner">
    <!-- Story -->
    <section class="story" aria-labelledby="story-heading">
      <h2 id="story-heading">What makes it different</h2>
      <p>
        Most AI assistants start fresh with every conversation and know nothing about
        you. sideBar is different: it builds a persistent picture of you from your
        notes, tasks, saved websites, files, and memories, and brings that context
        into every conversation automatically. When you ask sideBar a question, it
        can pull from your notes, check your tasks, or browse the web on your behalf,
        without you having to switch between apps or copy things around.
      </p>
      <p>
        sideBar also has its own identity and soul: a name, a tone of voice, a set of
        values, and a sense of purpose that evolve as it learns more about how you
        work. It is not a generic chat interface. It is an assistant that adapts to
        you over time.
      </p>
    </section>

    <!-- How it works -->
    <section class="story" aria-labelledby="how-heading">
      <h2 id="how-heading">How it works</h2>
      <p>
        sideBar works with Anthropic, OpenAI, and Google. You bring your own API key
        and pay those providers directly for the AI usage you generate. There is no
        subscription fee for sideBar itself, and you are never locked into a single
        model or company.
      </p>
      <p>
        The <a href="https://docs.trysidebar.ai/manual/skills-store">Skills Store</a>
        lets you extend sideBar with additional capabilities: transcribing audio and
        video, connecting to third-party services, and more. Skills run automatically
        during conversations when they are relevant, so you get the benefit without
        having to think about it.
      </p>
    </section>

    <!-- Contact -->
    <section class="contact" aria-labelledby="contact-heading">
      <h2 id="contact-heading">Get in touch</h2>
      <p>
        For support, feature requests, or anything else, email us at
        <a href="mailto:support@trysidebar.ai">support@trysidebar.ai</a>.
        The full documentation is at
        <a href="https://docs.trysidebar.ai">docs.trysidebar.ai</a>.
      </p>
    </section>
  </div> <!-- /page-inner -->
</div>

<style>
  .page {
    padding: 5rem 0;
  }

  .page-inner {
    max-width: 48rem;
    margin: 0 auto;
    padding: 0 1.5rem;
    display: flex;
    flex-direction: column;
    gap: 3rem;
  }

  .hero-image {
    max-width: 64rem;
    margin: 3rem auto;
    padding: 0 1.5rem;
  }

  .hero-image img {
    display: block;
    width: 100%;
    height: auto;
    border-radius: 0.75rem;
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

  .contact a,
  .story a {
    color: var(--color-foreground);
    text-decoration: underline;
    text-underline-offset: 3px;
  }

  .contact a:hover,
  .story a:hover {
    color: var(--color-muted-foreground);
  }
</style>
