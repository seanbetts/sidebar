<script lang="ts">
  import Seo from '$lib/components/Seo.svelte';

  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'WebPage',
    name: 'Privacy Policy',
    url: 'https://trysidebar.ai/privacy',
    description: 'How sideBar collects, uses, and protects your data.'
  };
</script>

<Seo
  title="Privacy Policy"
  description="How sideBar collects, uses, and protects your data."
  url="https://trysidebar.ai/privacy"
  {jsonLd}
/>

<div class="page">
  <div class="page-inner">
    <header>
      <h1>Privacy Policy</h1>
      <p class="meta">Last updated: March 8, 2026</p>
    </header>

    <section>
      <p>
        This Privacy Policy explains how sideBar ("we", "us", "our") collects, uses, and discloses
        information when you use the sideBar web app, iOS app, and related services.
      </p>
      <p>
        By using sideBar, you agree to the practices described in this policy. If you do not agree,
        please do not use the service.
      </p>
    </section>

    <section>
      <h2>1. Information We Collect</h2>
      <h3>Account Information</h3>
      <ul>
        <li>Email address and authentication identifiers</li>
        <li>Profile preferences and settings</li>
      </ul>
      <h3>Content You Provide</h3>
      <ul>
        <li>Prompts, chat history, tasks, notes, files, and saved website content</li>
        <li>Workspace metadata (such as titles, tags, and organisation choices)</li>
        <li>
          Memories: persistent reference documents created automatically by sideBar during
          conversations to improve future responses, as well as any memories you add or edit
          manually
        </li>
      </ul>
      <h3>Technical and Usage Data</h3>
      <ul>
        <li>Device, browser, and app version details</li>
        <li>Operational logs, error diagnostics, and performance telemetry</li>
        <li>IP address and approximate location derived from network requests</li>
        <li>
          Precise device location, if you grant location permission, used to provide local weather
          and location context to the assistant
        </li>
      </ul>
    </section>

    <section>
      <h2>2. How We Use Information</h2>
      <ul>
        <li>Provide, maintain, and secure sideBar functionality</li>
        <li>Process AI features and tool execution you request</li>
        <li>Sync your account data across supported clients</li>
        <li>Respond to support requests and service communications</li>
        <li>Improve product reliability, safety, and performance</li>
        <li>Comply with legal obligations and enforce our terms</li>
      </ul>
    </section>

    <section>
      <h2>3. AI Processing and Third-Party Services</h2>
      <p>
        sideBar uses a bring-your-own-key (BYOK) model for AI. You choose an AI provider (Anthropic,
        OpenAI, or Google) and supply your own API key in Settings. Your key is encrypted before
        being stored. When you use sideBar, your content is sent to the provider you have configured,
        not to all providers.
      </p>
      <p>
        To provide sideBar, we also use infrastructure and service providers that may process data
        on our behalf, including hosting, authentication, storage, and analytics. This can include
        providers such as Supabase, Cloudflare R2, Vercel, and Sentry. We require vendors to handle
        data under contractual and security controls appropriate for their role.
      </p>
      <h3>Store Skills and Third-Party Integrations</h3>
      <p>
        Some Store skills connect to external services (such as Gmail or Spotify). When you install
        and use such a skill, relevant data may be sent to that third-party service to fulfil your
        request. Each skill's requirements are shown before installation.
      </p>
      <h3>Bug Reports and Feedback</h3>
      <p>
        When you report a bug or request a feature via sideBar's built-in feedback tool, we collect
        a summary of your report along with technical metadata (such as your conversation ID and
        device information) and file it as an issue in our development tracker. No full conversation
        content is included.
      </p>
    </section>

    <section>
      <h2>4. Legal Bases (EEA/UK Users)</h2>
      <p>Where applicable, we process personal data under one or more of these legal bases:</p>
      <ul>
        <li>Contract: to provide the service you requested</li>
        <li>Legitimate interests: to secure and improve sideBar</li>
        <li>Consent: where you provide optional permissions</li>
        <li>Legal obligation: where required by law</li>
      </ul>
    </section>

    <section>
      <h2>5. Data Retention</h2>
      <p>
        We retain data for as long as needed to provide the service, meet legal obligations, resolve
        disputes, and enforce agreements. Retention periods vary by data type and operational need.
      </p>
      <p>
        When data is no longer required, we delete or de-identify it. Backup copies may persist for
        a limited period under standard disaster-recovery policies.
      </p>
    </section>

    <section>
      <h2>6. Data Sharing and Transfers</h2>
      <p>
        We do not sell your personal data. We may share data with service providers, affiliates, or
        legal authorities where necessary to operate sideBar, protect users, or comply with law.
      </p>
      <p>
        Your data may be processed in countries outside your own. Where required, we use appropriate
        transfer safeguards.
      </p>
    </section>

    <section>
      <h2>7. Your Rights and Choices</h2>
      <p>Depending on your location, you may have rights to:</p>
      <ul>
        <li>Access the personal data we hold about you</li>
        <li>Request correction or deletion of your data</li>
        <li>Object to or restrict certain processing</li>
        <li>Request data portability where applicable</li>
        <li>Withdraw consent where processing is based on consent</li>
      </ul>
      <p>
        To exercise these rights, contact us at
        <a href="mailto:support@trysidebar.ai">support@trysidebar.ai</a>.
      </p>
    </section>

    <section>
      <h2>8. Account and Data Deletion</h2>
      <p>
        You can request deletion of your account and associated data by emailing
        <a href="mailto:support@trysidebar.ai">support@trysidebar.ai</a> from your account email.
      </p>
      <p>
        We may request verification before deleting data and may retain limited records where
        required for legal, security, or fraud-prevention reasons.
      </p>
    </section>

    <section>
      <h2>9. Children's Privacy</h2>
      <p>
        sideBar is intended for users who meet the minimum age requirement in their region. Based on
        our current App Store ratings, sideBar is intended for users age 16+ in most regions, and
        15+ in Australia and the Republic of Korea.
      </p>
      <p>
        We do not knowingly collect personal data from children below the applicable minimum age. If
        you believe a child has provided personal data, contact
        <a href="mailto:support@trysidebar.ai">support@trysidebar.ai</a> and we will investigate
        and take appropriate action.
      </p>
    </section>

    <section>
      <h2>10. Changes to This Policy</h2>
      <p>
        We may update this Privacy Policy from time to time. If we make material changes, we will
        post the updated policy here and revise the "Last updated" date above.
      </p>
    </section>

    <section>
      <h2>11. Contact</h2>
      <p>
        For privacy questions or requests, contact:
        <a href="mailto:support@trysidebar.ai">support@trysidebar.ai</a>
      </p>
      <p>
        General inquiries:
        <a href="mailto:hello@trysidebar.ai">hello@trysidebar.ai</a>
      </p>
      <p>
        Administrative contact:
        <a href="mailto:admin@trysidebar.ai">admin@trysidebar.ai</a>
      </p>
    </section>
  </div>
</div>

<style>
  .page {
    padding: 4rem 1.5rem;
  }

  .page-inner {
    max-width: 48rem;
    margin: 0 auto;
  }

  header {
    margin-bottom: 2.5rem;
  }

  .meta {
    font-size: 0.875rem;
    color: var(--color-muted-foreground);
    margin: 0.25rem 0 0;
  }

  :global(.page-inner h1) {
    font-size: clamp(1.75rem, 3vw, 2.25rem);
    font-weight: 700;
    letter-spacing: -0.02em;
    margin: 0 0 0.25rem;
  }

  :global(.page-inner h2) {
    font-size: 1.125rem;
    font-weight: 600;
    margin: 2rem 0 0.75rem;
  }

  :global(.page-inner h3) {
    font-size: 1rem;
    font-weight: 600;
    margin: 1.5rem 0 0.5rem;
  }

  :global(.page-inner p) {
    font-size: 1rem;
    line-height: 1.7;
    color: var(--color-muted-foreground);
    margin: 0 0 1rem;
  }

  :global(.page-inner ul) {
    margin: 0 0 1rem;
    padding-left: 1.5rem;
  }

  :global(.page-inner li) {
    font-size: 1rem;
    line-height: 1.7;
    color: var(--color-muted-foreground);
    margin-bottom: 0.25rem;
  }

  :global(.page-inner a) {
    color: var(--color-foreground);
    text-decoration: underline;
    text-underline-offset: 3px;
  }

  :global(.page-inner a:hover) {
    color: var(--color-muted-foreground);
  }
</style>
