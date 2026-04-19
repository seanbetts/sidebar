<script lang="ts">
  import PixelDivider from '$lib/components/PixelDivider.svelte';
  import Seo from '$lib/components/Seo.svelte';
  import { MARKETING_COPY } from '../../../../shared/marketingCopy';

  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'AboutPage',
    name: 'About sideBar',
    url: 'https://trysidebar.ai/about',
    description: MARKETING_COPY.description
  };
</script>

<Seo
  title="About"
  description={MARKETING_COPY.description}
  url="https://trysidebar.ai/about"
  {jsonLd}
/>

<div class="page">
  <section class="story-section">
    <div class="page-shell page-shell--narrow prose-block">
      <p class="eyebrow">Founder note</p>
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
      <p>
        I became more and more convinced that most AI products still have the shape
        wrong. They are existing apps with AI bolted onto the side, when the more
        interesting opportunity is to build around an AI foundation from the start.
      </p>
      <p>
        I built sideBar for myself first. It started as a read-it-later tool because
        that was the job I needed most. Then I added notes. Then tasks. Over time,
        the things I used to spread across different apps started to come together
        in one place.
      </p>
      <p>
        That is the idea behind what I think of as AI-native productivity. The
        assistant should not be a detached chat box you visit separately. It should
        live inside the work surface itself, with access to the right context at the
        moment you need help.
      </p>
      <p>
        That also shaped the kind of assistant I wanted to build. I did not want a
        generic AI shell. I wanted sideBar to have a personality, a point of view,
        and enough self-awareness to help people understand what it can actually do
        instead of dropping them into a blank box and leaving them to figure it out.
      </p>
      <p>
        Skills are a big part of that. They are how sideBar grows over time. Some
        capabilities are built in, others can be added when they are genuinely
        useful, so the product can expand without turning into a messy collection of
        disconnected AI tricks.
      </p>
    </div>
  </section>
</div>

<style>
  .page {
    --page-width-narrow: 48rem;
    --page-gutter: 1.5rem;
    --page-body-size: clamp(1.02rem, 1vw + 0.82rem, 1.125rem);
    --page-heading-size: clamp(2.25rem, 4.2vw, 4rem);
    --page-body-leading: 1.7;
    --page-heading-leading: 0.94;
    padding: clamp(1rem, 2.5vw, 1.75rem) 0 0;
  }

  .story-section {
    position: relative;
  }

  .story-section {
    padding: clamp(1.75rem, 4vw, 2.5rem) 0 clamp(3.5rem, 6vw, 4.75rem);
  }

  .page-shell {
    margin: 0 auto;
    padding: 0 var(--page-gutter);
  }

  .page-shell--narrow {
    max-width: var(--page-width-narrow);
  }

  .eyebrow {
    margin: 0 0 0.5rem;
    font-size: 0.78rem;
    font-weight: 600;
    letter-spacing: 0.16em;
    text-transform: uppercase;
    color: var(--color-muted-foreground);
  }

  h2,
  p {
    margin: 0;
  }

  h2 {
    color: var(--color-foreground);
  }

  .prose-block {
    display: grid;
    gap: 0.875rem;
  }

  h2 {
    font-size: var(--page-heading-size);
    font-weight: var(--font-display-weight);
    line-height: var(--font-display-leading);
    letter-spacing: var(--font-display-tracking);
    text-wrap: balance;
  }

  .prose-block p {
    font-size: var(--page-body-size);
    line-height: var(--page-body-leading);
    color: var(--color-muted-foreground);
  }

  @media (max-width: 640px) {
    .page {
      --page-gutter: 1rem;
    }
  }
</style>
