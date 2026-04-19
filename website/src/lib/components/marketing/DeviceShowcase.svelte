<script lang="ts">
  type Props = {
    src: string;
    alt: string;
    width?: number | string;
    height?: number | string;
    loading?: 'eager' | 'lazy';
    decoding?: 'async' | 'auto' | 'sync';
    fetchpriority?: 'high' | 'low' | 'auto';
    class?: string;
    className?: string;
  };

  let {
    src,
    alt,
    width = 1366,
    height = 1024,
    loading = 'lazy',
    decoding = 'async',
    fetchpriority = 'auto',
    class: classProp = '',
    className = ''
  }: Props = $props();
</script>

<figure class={`device-showcase ${classProp} ${className}`.trim()}>
  <img {src} {alt} {width} {height} {loading} {decoding} {fetchpriority} />
</figure>

<style>
  .device-showcase {
    margin: 0;
    border: 1px solid var(--color-border);
    border-radius: calc(var(--radius) * 1.6);
    background: var(--card);
    overflow: hidden;
    box-shadow: 0 24px 60px -36px var(--shadow-color);
  }

  .device-showcase img {
    display: block;
    width: 100%;
    height: auto;
    background: var(--surface-strong);
  }
</style>
