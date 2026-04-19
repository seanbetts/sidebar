<script lang="ts">
  import Seo from '$lib/components/Seo.svelte';

  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'AboutPage',
    name: 'About sideBar',
    url: 'https://trysidebar.ai/about',
    description:
      'sideBar is an AI-native productivity app built around the belief that the assistant and the work environment should start together.'
  };
</script>

<Seo
  title="About"
  description="sideBar is an AI-native productivity app built around the belief that the assistant and the work environment should start together."
  url="https://trysidebar.ai/about"
  {jsonLd}
/>

<div class="page">
  <div class="page-inner">
    <header class="page-header">
      <p class="eyebrow">Founder note</p>
      <h1>About sideBar</h1>
      <p class="lead">
        sideBar is my attempt to make AI-native productivity feel natural: an
        assistant and a work environment designed together from day one.
      </p>
    </header>

    <div class="hero-image">
      <img
        src="/screenshots/overview.png"
        alt="sideBar on iPad showing the chat panel open alongside a website summary"
        width="1366"
        height="1024"
      />
    </div>

    <section class="story" aria-labelledby="story-heading">
      <h2 id="story-heading">Why I built sideBar</h2>
      <p>
        Most AI products still make people move context between tools, copy and
        paste into chat, and rebuild the same setup every time they want help. That
        copy-paste loop is the wrong shape for something that is supposed to save
        time.
      </p>
      <p>
        I kept running into the same friction: the model answer might be good, but I
        had to do too much manual setup to get there. The work lived in one place,
        the assistant lived in another, and the distance between them became the
        product.
      </p>
      <p>
        Claude Code made the idea click for me. It starts in the right environment,
        already surrounded by the files and context it needs. That changes the
        experience completely, because the assistant is not starting from a blank
        box. Personal AI should work more like that.
      </p>
      <p>
        sideBar started as my answer to that problem: a place where notes, tasks,
        saved pages, and the assistant stay close together so help begins from the
        context that is already there.
      </p>
    </section>

    <section class="story" aria-labelledby="native-heading">
      <h2 id="native-heading">AI-native productivity</h2>
      <p>
        AI-native productivity is the category I think is emerging now. It means the
        assistant is not bolted onto the edge of a product, it is built into the work
        surface itself.
      </p>
      <p>
        sideBar is heading in that direction. The product is designed so the assistant
        can understand what you have open, what you have saved, and what you are
        trying to finish without making you rebuild that context every time.
      </p>
      <p>
        That is why the site keeps talking about work rather than content. The goal is
        not to collect more stuff. It is to make it easier to do the work you already
        care about.
      </p>
    </section>

    <section class="contact" aria-labelledby="contact-heading">
      <h2 id="contact-heading">Get in touch</h2>
      <p>
        For support, feature requests, or early feedback, email
        <a href="mailto:support@trysidebar.ai">support@trysidebar.ai</a>.
        The full documentation lives at
        <a href="https://docs.trysidebar.ai">docs.trysidebar.ai</a>.
      </p>
    </section>
  </div>
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
    gap: 2rem;
  }

  .page-header,
  .story,
  .contact {
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
    font-size: 1.175rem;
    line-height: 1.6;
    color: var(--color-muted-foreground);
  }

  .hero-image {
    max-width: 64rem;
    margin: 0 auto;
    padding: 0 1.5rem;
  }

  .hero-image img {
    display: block;
    width: 100%;
    height: auto;
    border-radius: calc(var(--radius) * 1.2);
  }

  .story h2,
  .contact h2 {
    margin: 0;
    font-size: 1.25rem;
    font-weight: 600;
    letter-spacing: -0.01em;
  }

  .story p,
  .contact p {
    margin: 0;
    font-size: 1rem;
    line-height: 1.7;
    color: var(--color-muted-foreground);
  }

  .contact a {
    color: var(--color-foreground);
    text-decoration: underline;
    text-underline-offset: 3px;
  }

  .contact a:hover {
    color: var(--color-muted-foreground);
  }
</style>
