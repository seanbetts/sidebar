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
      <p class="meta">Last updated: 18 April 2026</p>
    </header>

    <section>
      <p>
        This Privacy Policy explains how sideBar Labs Limited ("sideBar", "we", "us", "our")
        collects, uses, and shares information when you use the sideBar iOS, iPadOS, and macOS apps,
        the sideBar web app at trysidebar.ai, and our related services (together, the "Service").
      </p>
      <p>
        sideBar Labs Limited is a company registered in England and Wales (company number
        17137829) with its registered office at 66 Paul Street, London, EC2A 4NA, and acts as the
        data controller for personal data processed through the Service. We are registered with the
        UK Information Commissioner's Office (ICO) under registration number ZC116277.
      </p>
      <p>
        By using sideBar you agree to the practices described in this policy. If you do not agree,
        please do not use the Service.
      </p>
    </section>

    <section>
      <h2>1. Information We Collect</h2>

      <h3>Account information</h3>
      <ul>
        <li>Email address and authentication identifiers</li>
        <li>Display name and profile preferences</li>
        <li>Subscription status and plan (Free, Plus, Pro, or BYOK)</li>
      </ul>

      <h3>Content you create or upload</h3>
      <ul>
        <li>Chat prompts, conversations, and AI responses</li>
        <li>Notes, tasks, files, and saved website content</li>
        <li>Workspace metadata such as titles, tags, and folder structure</li>
        <li>
          Memories: reference documents created automatically by sideBar during conversations to
          improve future responses, plus any memories you add or edit manually
        </li>
      </ul>

      <h3>Payment information</h3>
      <ul>
        <li>
          Web subscriptions are processed by Stripe. We do not receive or store full card details.
          We receive limited information such as your billing country, the last four digits of your
          card, and subscription status.
        </li>
        <li>
          iOS and macOS subscriptions are processed by Apple through In-App Purchase. Apple handles
          payment data and shares only the receipt and subscription status we need to unlock your
          plan.
        </li>
      </ul>

      <h3>Technical and usage data</h3>
      <ul>
        <li>Device type, operating system, browser, and app version</li>
        <li>Operational logs, crash reports, and performance telemetry</li>
        <li>IP address and approximate location derived from network requests</li>
        <li>
          Precise device location, if you grant permission, used only to provide local weather and
          location context to the assistant
        </li>
      </ul>

      <h3>Communications</h3>
      <ul>
        <li>Support emails and messages you send us</li>
        <li>Transactional emails we send you via Resend (for example, sign-in links and receipts)</li>
      </ul>
    </section>

    <section>
      <h2>2. How We Use Information</h2>
      <ul>
        <li>Provide, maintain, and secure the Service</li>
        <li>Process AI features, tool calls, and skills you request</li>
        <li>Sync your account across your devices and clients</li>
        <li>Process subscriptions, receipts, and renewals</li>
        <li>Send transactional messages (sign-in links, receipts, important service notices)</li>
        <li>Respond to support requests</li>
        <li>Diagnose crashes and improve product reliability, safety, and performance</li>
        <li>Comply with legal obligations and enforce our terms</li>
      </ul>
      <p>
        We do not use your chats, notes, tasks, files, or other content to train our own AI models,
        and we do not sell your personal data.
      </p>
    </section>

    <section>
      <h2>3. AI Processing</h2>
      <p>
        sideBar uses AI models provided by third-party vendors, currently Anthropic, OpenAI, and
        Google. How your content reaches those vendors depends on the plan you are on.
      </p>

      <h3>Bundled AI (Free, Plus, and Pro plans)</h3>
      <p>
        On our bundled plans, sideBar sends the prompts, conversation context, and any tool inputs
        needed to answer your request to the AI provider on your behalf using our own API accounts.
        Your content is processed under the AI provider's enterprise or API terms and is not used by
        them to train their foundation models.
      </p>

      <h3>Bring Your Own Key (BYOK)</h3>
      <p>
        On the BYOK plan you supply your own API key for an AI provider. Your key is encrypted
        before it is stored. When you use sideBar, your prompts and context are sent directly to the
        provider you chose using your key. That interaction is governed by your own agreement with
        that provider, and sideBar is not a party to it. We still handle the surrounding account,
        sync, and storage functions as described in this policy.
      </p>

      <h3>Store skills and third-party integrations</h3>
      <p>
        Some Store skills connect sideBar to external services (for example, Gmail, Google Calendar,
        or Spotify). When you install and use such a skill, relevant data is sent to that service to
        fulfil your request. Each skill's permissions are shown before installation, and you can
        disconnect it at any time in Settings.
      </p>

      <h3>Bug reports and feedback</h3>
      <p>
        When you report a bug or request a feature via sideBar's built-in feedback tool, we collect
        a summary of your report along with technical metadata (such as your conversation ID and
        device information) and file it as an issue in our development tracker. Full conversation
        content is not included unless you paste it in yourself.
      </p>
    </section>

    <section>
      <h2>4. Service Providers and Sub-processors</h2>
      <p>
        We use a small number of infrastructure and service providers to run sideBar. Each is bound
        by contractual and security controls appropriate to its role.
      </p>
      <ul>
        <li><strong>Supabase</strong>: authentication, database, and realtime sync</li>
        <li><strong>Fly.io</strong>: backend API hosting</li>
        <li><strong>Cloudflare</strong>: marketing site hosting, CDN, and DDoS protection</li>
        <li><strong>Cloudflare R2</strong>: file and object storage</li>
        <li><strong>Stripe</strong>: web subscription billing</li>
        <li><strong>Apple</strong>: iOS and macOS In-App Purchase billing</li>
        <li><strong>Resend</strong>: transactional email delivery</li>
        <li><strong>Sentry</strong>: crash and error reporting</li>
        <li><strong>Anthropic, OpenAI, Google</strong>: AI model providers</li>
      </ul>
      <p>
        This list may change as sideBar evolves. We will keep this page up to date when we add or
        change material sub-processors.
      </p>
    </section>

    <section>
      <h2>5. Legal Bases (UK and EEA Users)</h2>
      <p>Where UK or EU data protection law applies, we process personal data under these bases:</p>
      <ul>
        <li><strong>Contract</strong>: to provide the Service you signed up for</li>
        <li><strong>Legitimate interests</strong>: to secure, maintain, and improve sideBar</li>
        <li><strong>Consent</strong>: where you grant optional permissions such as location access</li>
        <li><strong>Legal obligation</strong>: where required by applicable law</li>
      </ul>
    </section>

    <section>
      <h2>6. Data Retention</h2>
      <p>
        We keep personal data only as long as needed for the purposes described in this policy or
        as required by law.
      </p>

      <h3>Account data</h3>
      <p>
        Account information is kept for as long as your account is active. If you close your
        account, we purge your account-scoped data immediately, subject to the limited exceptions
        below.
      </p>

      <h3>Content you delete</h3>
      <p>
        When you delete content inside sideBar we move it to a soft-deleted state for a short
        restore window and then remove it. We aim to apply roughly the following windows:
      </p>
      <ul>
        <li>Notes: restorable for around 7 days, hard-deleted within around 90 days</li>
        <li>Saved websites: restorable for around 7 days, hard-deleted within around 60 days</li>
        <li>Tasks, projects, and groups: hard-deleted within around 60 days</li>
        <li>
          Uploaded and ingested files: derivative storage is removed at delete time; the remaining
          metadata is hard-deleted within around 30 days
        </li>
        <li>BYOK provider API keys: hard-deleted within around 7 days of removal</li>
      </ul>
      <p>
        Restoration is only guaranteed during the initial restore window. After that window,
        limited metadata may be retained briefly to keep sync working across your devices, but the
        full content is no longer recoverable.
      </p>

      <h3>Account deletion</h3>
      <p>
        When you delete your sideBar account we trigger an immediate purge of your account-scoped
        data, including your chats, notes, tasks, files, memories, provider keys, and related
        operational records. Ordinary retention windows no longer apply once the account is
        deleted.
      </p>

      <h3>Operational data</h3>
      <p>
        Operational logs, job records, crash reports, and performance telemetry are typically kept
        for up to 90 days.
      </p>

      <h3>Billing and legal records</h3>
      <p>
        Billing records are kept for as long as required by tax and accounting law (generally up
        to 7 years in the UK). We may also retain limited records where needed for legal,
        security, or fraud-prevention reasons.
      </p>

      <h3>Backups</h3>
      <p>
        Backup copies may persist for a limited period under standard disaster-recovery policies
        before being overwritten.
      </p>
    </section>

    <section>
      <h2>7. Data Sharing and International Transfers</h2>
      <p>
        We do not sell your personal data. We share data with the service providers listed above,
        and with legal authorities where we are required by law or to protect the rights, property,
        or safety of sideBar, our users, or others.
      </p>
      <p>
        Some of our providers are based outside the UK and EEA, including in the United States.
        Where we transfer personal data outside the UK or EEA, we rely on appropriate safeguards
        such as the UK International Data Transfer Agreement (IDTA), the UK Addendum to the EU
        Standard Contractual Clauses, or an adequacy decision.
      </p>
    </section>

    <section>
      <h2>8. Cookies and Browser Storage</h2>
      <p>
        sideBar does not set advertising cookies and does not use third-party tracking cookies. The
        Service relies on browser storage (localStorage, sessionStorage, and a small number of
        first-party cookies set by our infrastructure providers) purely to keep you signed in and to
        remember your preferences.
      </p>

      <h3>What we store in your browser</h3>
      <ul>
        <li>
          <strong>Authentication tokens</strong>: set by Supabase so you stay signed in between
          visits. Cleared when you sign out or when the session expires.
        </li>
        <li>
          <strong>Theme and layout preferences</strong>: your light/dark theme choice and sidebar
          layout, so the app looks the way you left it.
        </li>
        <li>
          <strong>Weather and location preferences</strong>: cached weather data, your Fahrenheit or
          Celsius choice, and a short-lived cache of your location if you granted permission, so the
          header does not have to re-fetch on every load.
        </li>
        <li>
          <strong>Infrastructure cookies</strong>: essential first-party cookies set by Cloudflare
          and Fly.io for security, bot protection, and request routing.
        </li>
      </ul>

      <p>
        All of this storage is essential or functional. We do not use browser storage for
        advertising, cross-site tracking, or analytics that profile you across other websites.
        Because the storage is limited to what the Service needs to function, a cookie consent
        banner is not required under UK and EU ePrivacy rules, but this section explains what is
        happening so you can make an informed choice.
      </p>

      <p>
        You can clear this data at any time through your browser settings. Clearing it will sign
        you out and reset your preferences. On our iOS and macOS apps, equivalent local data is
        stored in the app container and is removed when you delete the app or sign out.
      </p>
    </section>

    <section>
      <h2>9. Security</h2>
      <p>
        We use industry-standard measures to protect your data, including encryption in transit
        (TLS), encryption at rest for sensitive data, certificate pinning on our apps, encrypted
        storage of BYOK API keys, and access controls on our infrastructure. No online service can
        be completely secure, but we work to reduce risk and respond quickly to incidents.
      </p>
    </section>

    <section>
      <h2>10. Your Rights</h2>
      <p>Depending on where you live, you may have the right to:</p>
      <ul>
        <li>Access the personal data we hold about you</li>
        <li>Request correction or deletion of your data</li>
        <li>Object to or restrict certain processing</li>
        <li>Request data portability</li>
        <li>Withdraw consent where processing is based on consent</li>
      </ul>
      <p>
        To exercise any of these rights, email
        <a href="mailto:support@trysidebar.ai">support@trysidebar.ai</a> from your account email.
        We may ask you to verify your identity before we act.
      </p>
      <p>
        If you are in the UK or EEA and you are not happy with how we have handled your data, you
        have the right to complain to your local data protection authority. In the UK this is the
        Information Commissioner's Office (<a href="https://ico.org.uk">ico.org.uk</a>).
      </p>
    </section>

    <section>
      <h2>11. Account and Data Deletion</h2>
      <p>
        You can request deletion of your account and associated content by emailing
        <a href="mailto:support@trysidebar.ai">support@trysidebar.ai</a> from your account email.
        We may retain limited records where required for legal, security, tax, or fraud-prevention
        reasons.
      </p>
    </section>

    <section>
      <h2>12. Children's Privacy</h2>
      <p>
        sideBar is intended for users aged 18 and over. It is not designed for children or
        teenagers, and we do not knowingly collect personal data from anyone under 18.
      </p>
      <p>
        If you believe someone under 18 has provided personal data to us, contact
        <a href="mailto:support@trysidebar.ai">support@trysidebar.ai</a> and we will investigate
        and delete the data where appropriate.
      </p>
    </section>

    <section>
      <h2>13. Changes to This Policy</h2>
      <p>
        We may update this Privacy Policy from time to time. If we make material changes, we will
        post the updated policy here and revise the "Last updated" date above. For significant
        changes we will also give you a reasonable in-app or email notice where appropriate.
      </p>
    </section>

    <section>
      <h2>14. Contact</h2>
      <p>
        sideBar Labs Limited, a company registered in England and Wales under company number
        17137829. ICO registration number ZC116277. Registered office: 66 Paul Street, London,
        EC2A 4NA.
      </p>
      <p>
        Privacy questions or requests:
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
</style>
