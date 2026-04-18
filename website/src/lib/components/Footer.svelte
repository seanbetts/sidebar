<footer class="footer">
  <div class="footer-inner">
    <p class="copy">
      &copy; {new Date().getFullYear()} sideBar Labs Limited. All rights reserved.
    </p>
    <p class="registered">
      Registered in England and Wales, company number 17137829. Registered office: 66 Paul Street,
      London, EC2A 4NA.
    </p>
    <nav class="footer-links" aria-label="Footer navigation">
      <a href="/privacy">Privacy Policy</a>
      <a href="/terms">Terms of Service</a>
      <a href="/eula">EULA</a>
      <a href="mailto:support@trysidebar.ai">Contact</a>
    </nav>
    <p class="made-with">
      Made with <span class="heart">&hearts;</span> and
      <a href="https://openai.com/codex/" target="_blank" rel="noopener noreferrer">Codex</a>
    </p>
  </div>
</footer>

<style>
  .footer {
    border-top: 1px solid var(--color-border);
    padding: 2rem 1.5rem;
    margin-top: 6rem;
  }

  .footer-inner {
    max-width: 72rem;
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.75rem;
    text-align: center;
  }

  .copy,
  .registered,
  .made-with {
    margin: 0;
    font-size: 0.8125rem;
    color: var(--color-muted-foreground);
  }

  .footer-links {
    display: flex;
    gap: 1.25rem;
  }

  .footer-links a {
    font-size: 0.8125rem;
    color: var(--color-muted-foreground);
    text-decoration: underline;
    text-underline-offset: 2px;
  }

  .footer-links a:hover {
    color: var(--color-foreground);
  }

  .made-with a {
    color: var(--color-muted-foreground);
    text-decoration: underline;
    text-underline-offset: 2px;
  }

  .heart {
    color: var(--color-foreground);
  }
</style>
