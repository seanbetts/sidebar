<script lang="ts">
  type Props = {
    name: string;
    status?: string;
    price: string;
    subtitle?: string;
    summary: string;
    bullets: string[];
  };

  let { name, status, price, subtitle, summary, bullets }: Props = $props();
</script>

<article class="tier-card">
  <header class="tier-header">
    <div class="tier-topline">
      <h2 class="tier-name">{name}</h2>
      {#if status}
        <p class="tier-status">{status}</p>
      {/if}
    </div>
    <div class="tier-pricing">
      <p class="tier-price">{price}</p>
      {#if subtitle}
        <p class="tier-subtitle">{subtitle}</p>
      {/if}
    </div>
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
    gap: 0.5rem;
  }

  .tier-topline {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 0.75rem;
  }

  .tier-name,
  .tier-price,
  .tier-subtitle,
  .tier-summary,
  .tier-status {
    margin: 0;
  }

  .tier-pricing {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 1rem;
  }

  .tier-name {
    font-size: 0.85rem;
    font-weight: 600;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--color-muted-foreground);
  }

  .tier-status {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-height: 1.6rem;
    padding: 0.2rem 0.55rem;
    border: 1px solid var(--color-border);
    border-radius: 999px;
    background: var(--color-secondary);
    font-size: 0.72rem;
    font-weight: 600;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--color-muted-foreground);
    white-space: nowrap;
  }

  .tier-price {
    font-family: var(--font-display);
    font-size: clamp(1.75rem, 4vw, 2.5rem);
    font-weight: var(--font-display-weight);
    line-height: var(--font-display-leading);
    letter-spacing: var(--font-display-tracking);
    color: var(--color-foreground);
  }

  .tier-subtitle {
    font-family: var(--font-display);
    font-size: 1.1rem;
    font-weight: var(--font-display-weight);
    line-height: 1;
    letter-spacing: var(--font-display-compact-tracking);
    color: var(--color-foreground);
    text-align: right;
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
