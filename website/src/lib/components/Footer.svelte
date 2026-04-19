<script lang="ts">
  import PixelDivider from '$lib/components/PixelDivider.svelte';
</script>

<footer class="footer">
  <PixelDivider position="top" />
  <div class="footer-inner">
    <div class="footer-brand" aria-label="sideBar brand">
      <span class="footer-brand__mark" aria-hidden="true">
        <img
          class="footer-brand__asset footer-brand__asset--light"
          src="/logo-animated-light.gif"
          alt=""
          width="56"
          height="56"
        />
        <img
          class="footer-brand__asset footer-brand__asset--dark"
          src="/logo-animated-dark.gif"
          alt=""
          width="56"
          height="56"
        />
      </span>
      <span class="footer-brand__name">sideBar</span>
    </div>
    <p class="copy">
      &copy; {new Date().getFullYear()} sideBar Labs Limited. All rights reserved.
    </p>
    <div class="footer-meta">
      <p class="registered">
        Registered in England and Wales, company number 17137829.
      </p>
      <p class="registered">
        Registered office: 66 Paul Street, London, EC2A 4NA.
      </p>
    </div>
    <nav class="footer-links" aria-label="Footer legal and support links">
      <a href="/privacy">Privacy Policy</a>
      <a href="/terms">Terms of Service</a>
      <a href="/eula">EULA</a>
      <a href="mailto:support@trysidebar.ai">Contact</a>
    </nav>
  </div>
</footer>

<style>
  .footer {
    position: relative;
    padding: 2.5rem 1.5rem;
    margin-top: 6rem;
  }

  .footer-inner {
    max-width: 72rem;
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 1rem;
    text-align: center;
  }

  .footer-brand {
    display: inline-flex;
    align-items: center;
    gap: 1rem;
    color: var(--color-foreground);
    width: fit-content;
    margin-bottom: 0.5rem;
  }

  .footer-brand__mark {
    position: relative;
    display: inline-grid;
    place-items: center;
    width: 3.5rem;
    height: 3.5rem;
  }

  .footer-brand__asset {
    grid-area: 1 / 1;
    display: block;
    width: 100%;
    height: 100%;
  }

  .footer-brand__asset--dark {
    display: none;
  }

  :global(.dark) .footer-brand__asset--light {
    display: none;
  }

  :global(.dark) .footer-brand__asset--dark {
    display: block;
  }

  .footer-brand__name {
    font-size: 2.75rem;
    font-weight: 650;
    letter-spacing: -0.03em;
    line-height: 1;
  }

  .copy,
  .registered {
    margin: 0;
    max-width: 40rem;
    font-size: 0.8125rem;
    line-height: 1.6;
    color: var(--color-muted-foreground);
  }

  .footer-meta {
    display: grid;
    gap: 0.125rem;
  }

  .footer-links {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: 0.75rem 1.25rem;
  }

  .footer-links a {
    font-size: 0.8125rem;
    font-weight: 500;
    color: var(--color-muted-foreground);
    text-decoration: underline;
    text-underline-offset: 2px;
    transition: color 0.15s ease;
  }

  .footer-links a:hover {
    color: var(--color-foreground);
  }

  @media (max-width: 640px) {
    .footer-brand {
      gap: 0.875rem;
    }

    .footer-brand__mark {
      width: 3rem;
      height: 3rem;
    }

    .footer-brand__name {
      font-size: 2.25rem;
    }
  }
</style>
