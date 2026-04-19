<script lang="ts">
  type Props = {
    name: string;
    price: string;
    summary: string;
    bullets: string[];
  };

  let { name, price, summary, bullets }: Props = $props();
</script>

<article class="tier-card">
  <header class="tier-header">
    <h2 class="tier-name">{name}</h2>
    <p class="tier-price">{price}</p>
  </header>

  <p class="tier-summary">{summary}</p>

  {#if bullets.length > 0}
    <ul class="tier-bullets" aria-label={`${name} features`}>
      {#each bullets as bullet}
        <li>{bullet}</li>
      {/each}
    </ul>
  {/if}
</article>

<style>
  .tier-card {
    display: grid;
    gap: 1.25rem;
    padding: 1.5rem;
    border: 1px solid var(--color-border);
    border-radius: calc(var(--radius) * 1.4);
    background: var(--card);
    color: var(--color-card-foreground);
    box-shadow: 0 24px 60px -36px var(--shadow-color);
  }

  .tier-header {
    display: grid;
    gap: 0.4rem;
  }

  .tier-name,
  .tier-price,
  .tier-summary {
    margin: 0;
  }

  .tier-name {
    font-size: 0.85rem;
    font-weight: 600;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--color-muted-foreground);
  }

  .tier-price {
    font-size: clamp(1.75rem, 4vw, 2.5rem);
    font-weight: 700;
    letter-spacing: -0.04em;
    color: var(--color-foreground);
  }

  .tier-summary {
    font-size: 0.95rem;
    line-height: 1.65;
    color: var(--color-muted-foreground);
  }

  .tier-bullets {
    display: grid;
    gap: 0.75rem;
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .tier-bullets li {
    position: relative;
    padding-left: 1rem;
    line-height: 1.55;
  }

  .tier-bullets li::before {
    content: '';
    position: absolute;
    top: 0.72em;
    left: 0;
    width: 0.35rem;
    height: 0.35rem;
    border-radius: 999px;
    background: var(--color-foreground);
  }
</style>
