<script lang="ts">
  import DeviceShowcase, { type DeviceShowcaseMedia } from './DeviceShowcase.svelte';

  type Props = {
    heading: string;
    body: string;
    media: DeviceShowcaseMedia;
    reverse?: boolean;
  };

  let { heading, body, media, reverse = false }: Props = $props();
</script>

<section class:reverse={reverse} class="proof-section">
  <div class="proof-copy">
    <h2>{heading}</h2>
    <p>{body}</p>
  </div>

  <div class="proof-media">
    <DeviceShowcase {media} chrome={media.kind === 'image' ? 'bare' : 'framed'} />
  </div>
</section>

<style>
  .proof-section {
    max-width: 78rem;
    margin: 0 auto;
    padding: clamp(3.5rem, 8vw, 5.5rem) 1.5rem;
    border-top: 1px solid var(--color-border);
    display: grid;
    grid-template-columns:
      minmax(0, 1fr)
      minmax(18rem, var(--marketing-device-ipad-width, 40rem));
    gap: clamp(1.75rem, 5vw, 4rem);
    align-items: center;
  }

  .proof-copy {
    display: grid;
    gap: 1rem;
    max-width: 28rem;
  }

  .proof-copy h2,
  .proof-copy p {
    margin: 0;
  }

  .proof-copy h2 {
    font-size: clamp(2.25rem, 5vw, 4rem);
    line-height: 0.96;
    letter-spacing: -0.055em;
    color: var(--color-foreground);
  }

  .proof-copy p {
    font-size: 1rem;
    line-height: 1.75;
    color: var(--color-muted-foreground);
  }

  .proof-media {
    transition:
      transform 0.2s ease,
      filter 0.2s ease;
  }

  .reverse .proof-copy {
    order: 2;
    justify-self: end;
  }

  .reverse .proof-media {
    order: 1;
  }

  @media (prefers-reduced-motion: no-preference) {
    .proof-section:hover .proof-media {
      transform: translateY(-0.25rem);
      filter: brightness(1.01);
    }
  }

  @media (max-width: 760px) {
    .proof-section {
      grid-template-columns: 1fr;
      padding-inline: 1rem;
    }

    .proof-copy,
    .reverse .proof-copy {
      order: initial;
      justify-self: start;
      max-width: none;
    }

    .reverse .proof-media {
      order: initial;
    }
  }
</style>
