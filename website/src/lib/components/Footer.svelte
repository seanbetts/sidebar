<footer class="footer">
  <div class="footer-inner">
    <p class="copy">
      &copy; {new Date().getFullYear()} sideBar Labs Limited. All rights reserved.
    </p>
    <p class="registered">
      Registered in England and Wales, company number 17137829. Registered office: 66 Paul Street, London, EC2A 4NA.
    </p>
    <nav class="footer-links" aria-label="Footer navigation">
      <a href="/about">About</a>
      <a href="/pricing">Pricing</a>
      <a href="https://docs.trysidebar.ai">Docs</a>
      <a href="/privacy">Privacy Policy</a>
      <a href="/terms">Terms of Service</a>
      <a href="/eula">EULA</a>
      <a href="mailto:support@trysidebar.ai">Contact</a>
    </nav>
  </div>
</footer>

<style>
  .footer {
    border-top: 1px solid var(--color-border);
    background: var(--surface);
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

  .copy,
  .registered {
    margin: 0;
    max-width: 40rem;
    font-size: 0.8125rem;
    line-height: 1.6;
    color: var(--color-muted-foreground);
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
</style>
