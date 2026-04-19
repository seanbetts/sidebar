<script lang="ts">
  export type ImageMedia = {
    kind: 'image';
    src: string;
    alt: string;
    frame?: 'ipad' | 'iphone';
    width?: number | string;
    height?: number | string;
    loading?: 'eager' | 'lazy';
    decoding?: 'async' | 'auto' | 'sync';
    fetchpriority?: 'high' | 'low' | 'auto';
  };

  export type PlaceholderMedia = {
    kind: 'placeholder';
    label: string;
    frame?: 'ipad' | 'iphone';
    width?: number | string;
    height?: number | string;
  };

  export type DeviceShowcaseMedia = ImageMedia | PlaceholderMedia;

  type Props = {
    media: DeviceShowcaseMedia;
    class?: string;
    chrome?: 'framed' | 'bare';
  };

  let {
    media,
    class: classProp = '',
    chrome = 'framed'
  }: Props = $props();

  let frame = $derived(media.frame ?? 'ipad');
  let width = $derived(media.width ?? (frame === 'iphone' ? 430 : 1366));
  let height = $derived(media.height ?? (frame === 'iphone' ? 932 : 1024));
  let classes = $derived(
    ['device-showcase', `device-showcase--${frame}`, `device-showcase--${chrome}`, classProp]
      .filter(Boolean)
      .join(' ')
  );
</script>

<figure class={classes}>
  {#if media.kind === 'image'}
    <img
      src={media.src}
      alt={media.alt}
      width={width}
      height={height}
      loading={media.loading ?? 'lazy'}
      decoding={media.decoding ?? 'async'}
      fetchpriority={media.fetchpriority ?? 'auto'}
    />
  {:else}
    <div
      class="device-placeholder"
      role="img"
      aria-label={media.label}
      style={`aspect-ratio: ${width} / ${height};`}
    >
      <span aria-hidden="true">{media.label}</span>
    </div>
  {/if}
</figure>

<style>
  .device-showcase {
    --device-showcase-max-width: var(--marketing-device-ipad-width, 40rem);
    margin: 0;
    inline-size: min(100%, var(--device-showcase-max-width));
    border: 1px solid var(--color-border);
    border-radius: calc(var(--radius) * 1.6);
    background: var(--card);
    overflow: hidden;
    box-shadow: 0 24px 60px -36px var(--shadow-color);
  }

  .device-showcase--ipad {
    --device-showcase-max-width: var(--marketing-device-ipad-width, 40rem);
  }

  .device-showcase--iphone {
    --device-showcase-max-width: var(--marketing-device-iphone-width, 20rem);
    border-radius: calc(var(--radius) * 2);
  }

  .device-showcase--bare {
    border: 0;
    border-radius: 0;
    background: transparent;
    box-shadow: none;
    overflow: visible;
  }

  .device-showcase img,
  .device-placeholder {
    display: block;
    width: 100%;
  }

  .device-showcase img {
    height: auto;
    background: var(--surface-strong);
  }

  .device-showcase--bare img {
    background: transparent;
  }

  .device-placeholder {
    display: grid;
    place-items: center;
    box-sizing: border-box;
    padding: clamp(1.25rem, 4vw, 2.5rem);
    background: var(--surface-strong);
    box-shadow: inset 0 0 0 1px var(--color-border);
    color: var(--color-muted-foreground);
    text-align: center;
  }

  .device-placeholder span {
    max-width: 12ch;
    font-size: 0.98rem;
    line-height: 1.4;
    letter-spacing: -0.02em;
  }
</style>
