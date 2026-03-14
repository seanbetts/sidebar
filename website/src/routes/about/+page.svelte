<script lang="ts">
  import Seo from '$lib/components/Seo.svelte';

  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'AboutPage',
    name: 'About sideBar',
    url: 'https://trysidebar.ai/about',
    description:
      'sideBar is an AI assistant for iPhone, iPad, Mac, and web, built around the belief that the assistant should be the foundation of the product, not a feature bolted onto the edge of it.'
  };
</script>

<Seo
  title="About"
  description="sideBar is an AI assistant for iPhone, iPad, Mac, and web, built around the belief that the assistant should be the foundation of the product, not a feature bolted onto the edge of it."
  url="https://trysidebar.ai/about"
  {jsonLd}
/>

<div class="page">
  <div class="page-inner">
    <!-- Header -->
    <header class="page-header">
      <h1>About sideBar</h1>
      <p class="lead">
        An AI assistant for iPhone, iPad, Mac, and web, built around the belief
        that the assistant should be the foundation of the product, not a feature
        bolted onto the edge of it.
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
    <!-- Founder story -->
    <section class="story" aria-labelledby="story-heading">
      <h2 id="story-heading">Why I built sideBar</h2>
      <p>
        I got tired of copying things in and out of ChatGPT and Claude. Attaching
        files. Explaining the same context again and again. Jumping between notes
        apps, task managers, read-it-later tools, and AI chat windows, trying to
        stitch everything together into something that actually felt useful.
      </p>
      <p>
        The models kept improving. The product experience around them often still
        felt wrong.
      </p>
      <p>
        The thing that made it click was Claude Code. You spin it up inside a folder
        and it can immediately work with the files around it. That sounds simple, but
        it changes the feeling completely: the AI starts in the right environment and
        can do something useful with what is already there. I kept thinking: why
        doesn't personal AI work more like this?
      </p>
      <p>
        So I started building sideBar. I began with a read-it-later service, because
        that was what I reached for most. Then I added notes, then tasks. Over time,
        I found I was no longer opening the separate apps I had used for those
        things. That was the moment it stopped feeling like a side project.
      </p>
    </section>

    <!-- What makes it different -->
    <section class="story" aria-labelledby="different-heading">
      <h2 id="different-heading">What makes it different</h2>
      <p>
        Most AI assistants sit inside a blank chat interface and know nothing about
        you until you tell them. sideBar is different because it was built the other
        way around: your content lives alongside your assistant, so it has real
        context to work with from the start.
      </p>
      <p>
        sideBar also knows what it can do and how it works, which sounds obvious but
        is rarer than it should be. It can guide you through its own capabilities,
        rather than leaving you to figure it out.
      </p>
      <p>
        And it has its own identity: a name, a tone of voice, a set of values. Not a
        generic AI shell. An assistant that is designed to feel like it is on your
        side.
      </p>
    </section>

    <!-- How it works -->
    <section class="story" aria-labelledby="how-heading">
      <h2 id="how-heading">How sideBar works</h2>
      <p>
        sideBar works with Anthropic, OpenAI, and Google. You bring your own API key
        and pay those providers directly for the AI usage you generate. You are never
        locked into a single model or company.
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
