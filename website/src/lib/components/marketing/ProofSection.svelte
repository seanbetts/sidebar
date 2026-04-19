<script lang="ts">
  import DeviceShowcase, { type DeviceShowcaseMedia } from './DeviceShowcase.svelte';

  type Props = {
    heading: string;
    body: string;
    media: DeviceShowcaseMedia;
    reverse?: boolean;
  };

  let { heading, body, media, reverse = false }: Props = $props();
  let frame = $derived(media.frame ?? 'ipad');
</script>

<section class:reverse={reverse} class:proof-section--iphone={frame === 'iphone'} class="proof-section">
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
    --proof-media-width: var(--marketing-device-ipad-width, 40rem);
    max-width: var(--marketing-page-width, 78rem);
    margin: 0 auto;
    padding: clamp(3.5rem, 8vw, 5.5rem) var(--marketing-page-gutter, 1.5rem);
    display: grid;
    grid-template-columns:
      minmax(0, 1fr)
      minmax(16rem, var(--proof-media-width));
    gap: clamp(1.75rem, 5vw, 4rem);
    align-items: center;
    position: relative;
  }

  .proof-section--iphone {
    --proof-media-width: var(--marketing-device-iphone-width, 20rem);
  }

  .proof-section::before {
    content: '';
    position: absolute;
    top: 0;
    left: 50%;
    width: 100vw;
    border-top: 1px solid var(--color-border);
    transform: translateX(-50%);
  }

  .proof-copy {
    display: grid;
    gap: 1.125rem;
    max-width: var(--marketing-home-copy-max, 31rem);
  }

  .proof-copy h2,
  .proof-copy p {
    margin: 0;
  }

  .proof-copy h2 {
    font-size: var(--marketing-home-heading-size, clamp(2.4rem, 4vw + 1.4rem, 3.85rem));
    line-height: var(--marketing-home-heading-leading, 0.98);
    letter-spacing: -0.05em;
    color: var(--color-foreground);
    text-wrap: balance;
  }

  .proof-copy p {
    font-size: var(--marketing-home-body-size, clamp(1.02rem, 1vw + 0.82rem, 1.125rem));
    line-height: var(--marketing-home-body-leading, 1.68);
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
