<script lang="ts">
  import Seo from '$lib/components/Seo.svelte';

  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'WebPage',
    name: 'Terms of Service',
    url: 'https://trysidebar.ai/terms',
    description: 'The terms that govern your use of sideBar.'
  };
</script>

<Seo
  title="Terms of Service"
  description="The terms that govern your use of sideBar."
  url="https://trysidebar.ai/terms"
  {jsonLd}
/>

<div class="page">
  <div class="page-inner">
    <header>
      <h1>Terms of Service</h1>
      <p class="meta">Last updated: 11 April 2026</p>
    </header>

    <section>
      <p>
        These Terms of Service ("Terms") are a legal agreement between you and sideBar Labs
        Limited, a company registered in England and Wales under company number 17137829
        ("sideBar", "we", "us", "our"). They govern your use of the sideBar iOS, iPadOS, and macOS
        apps, the sideBar web app at trysidebar.ai, and our related services (together, the
        "Service").
      </p>
      <p>
        By creating an account or using the Service you agree to these Terms. If you do not agree,
        please do not use the Service.
      </p>
      <p>
        Please also read our
        <a href="/privacy">Privacy Policy</a>, which explains how we handle your personal data and
        forms part of these Terms.
      </p>
    </section>

    <section>
      <h2>1. Who can use sideBar</h2>
      <p>
        You must be at least 18 years old to create an account and use sideBar. By using the
        Service you confirm that you are 18 or older. sideBar is not intended for children or
        teenagers.
      </p>
      <p>
        You are responsible for your account, for keeping your login credentials secure, and for
        everything that happens under your account. Let us know at
        <a href="mailto:support@trysidebar.ai">support@trysidebar.ai</a> if you think your account
        has been compromised.
      </p>
    </section>

    <section>
      <h2>2. Your content</h2>
      <p>
        You keep ownership of the content you create or upload through sideBar, including your
        chats, notes, tasks, files, and memories ("Your Content"). You grant us a worldwide,
        non-exclusive, royalty-free licence to host, store, process, transmit, and display Your
        Content solely so we can provide, secure, and improve the Service for you.
      </p>
      <p>
        We do not use Your Content to train our own AI models. We do not sell Your Content.
      </p>
      <p>
        You are responsible for Your Content and for having the rights you need to upload or share
        it. You must not upload content that infringes someone else's rights, is illegal, or breaks
        our acceptable use rules below.
      </p>
    </section>

    <section>
      <h2>3. Subscription plans and billing</h2>
      <p>
        sideBar offers a free plan and paid plans (currently Plus, Pro, and BYOK). The features,
        usage limits, and prices for each plan are shown inside the app and on our website when you
        sign up. We may change plans, prices, or features from time to time; where we do, we will
        give you reasonable notice and your existing paid term will generally run out at the price
        you originally agreed.
      </p>

      <h3>Web subscriptions (Stripe)</h3>
      <p>
        Subscriptions purchased through our web app are billed by Stripe. Payments renew
        automatically at the end of each billing period (monthly or yearly) until you cancel. You
        can cancel at any time from your account settings; cancellation takes effect at the end of
        your current paid period and you keep access until then.
      </p>

      <h3>Apple subscriptions (In-App Purchase)</h3>
      <p>
        Subscriptions purchased on iOS or macOS are billed by Apple through In-App Purchase. They
        renew automatically through your Apple ID and are managed in your Apple account settings.
        Refunds for Apple subscriptions are handled by Apple under its standard refund policy.
      </p>

      <h3>Bring Your Own Key (BYOK)</h3>
      <p>
        BYOK plan subscribers supply their own API key for a supported AI provider. AI usage on the
        BYOK plan is billed to you directly by that provider under your own agreement with them.
        sideBar is not responsible for those charges.
      </p>

      <h3>UK and EU cancellation rights</h3>
      <p>
        If you are a consumer in the UK or EU you normally have 14 days from the start of a new
        subscription to cancel and receive a refund. Because sideBar is a digital service that is
        made available immediately, you agree that we can start providing the Service as soon as
        you subscribe, and you accept that you lose the statutory cancellation right for that
        period once we have started providing the Service. You can still cancel future renewals at
        any time as described above. For Apple subscriptions, cancellations and refunds are handled
        through Apple.
      </p>
    </section>

    <section>
      <h2>4. Free plan and fair use</h2>
      <p>
        The free plan is offered on a "fair use" basis. We may apply reasonable rate limits or
        usage caps to protect the Service and other users. We may change these limits over time and
        will try to do so fairly and with notice where practical.
      </p>
    </section>

    <section>
      <h2>5. Acceptable use</h2>
      <p>You agree not to use the Service to:</p>
      <ul>
        <li>Break any applicable law or regulation</li>
        <li>Infringe anyone else's intellectual property, privacy, or other rights</li>
        <li>
          Generate or distribute content that is illegal, sexually exploitative of minors, harmful,
          harassing, defamatory, or designed to deceive
        </li>
        <li>Attempt to reverse engineer, scrape, or extract source code from the Service</li>
        <li>Resell, sublicense, or provide the Service to third parties as a hosted offering</li>
        <li>
          Probe, disrupt, or overload the Service or any connected infrastructure, or circumvent
          security, rate-limit, or access controls
        </li>
        <li>Use the Service to build a competing product or to train another AI system</li>
        <li>
          Use automated agents to generate high volumes of requests beyond normal personal use
        </li>
      </ul>
      <p>
        If you break these rules we may suspend or close your account. Where reasonable we will try
        to warn you first.
      </p>
    </section>

    <section>
      <h2>6. AI features and disclaimer</h2>
      <p>
        sideBar uses third-party AI models (currently from Anthropic, OpenAI, and Google). AI
        output can be inaccurate, incomplete, biased, or offensive, and will not always reflect
        recent events or your specific situation. You must not treat AI output as legal, medical,
        financial, or other professional advice.
      </p>
      <p>
        You are responsible for checking AI output before you rely on it, share it, or act on it.
        You are also responsible for any tools, actions, or integrations that you let sideBar
        trigger on your behalf, such as sending emails or modifying calendar events through an
        installed Store skill.
      </p>
    </section>

    <section>
      <h2>7. Third-party services</h2>
      <p>
        The Service relies on third-party providers including Apple, Stripe, Supabase, Cloudflare,
        Fly.io, Resend, Sentry, Anthropic, OpenAI, and Google. Your use of those services may also
        be subject to their own terms. If you install a Store skill that connects to a third-party
        service (for example, Gmail or Spotify), that service's own terms apply to your use of it.
      </p>
    </section>

    <section>
      <h2>8. Changes to the Service</h2>
      <p>
        sideBar is an evolving product. We may add, change, or remove features, and we may change
        these Terms from time to time. If we make material changes, we will post the updated Terms
        here, revise the "Last updated" date, and where appropriate give you in-app or email
        notice. Continuing to use the Service after a change takes effect means you accept the
        updated Terms.
      </p>
    </section>

    <section>
      <h2>9. Termination</h2>
      <p>
        You can stop using sideBar at any time and close your account by emailing
        <a href="mailto:support@trysidebar.ai">support@trysidebar.ai</a>. We may suspend or close
        your account if you break these Terms, if we are required to by law, or if we need to
        protect the Service or other users. If we close your paid account without good reason we
        will refund the unused part of your current billing period on a pro-rata basis (Apple
        subscriptions are refunded through Apple).
      </p>
      <p>
        When your account is closed we trigger an immediate purge of your account-scoped content
        as described in our <a href="/privacy">Privacy Policy</a>, subject to the limited legal,
        billing, and backup exceptions set out there.
      </p>
    </section>

    <section>
      <h2>10. Warranties</h2>
      <p>
        We provide the Service with reasonable care and skill. Beyond that, and to the fullest
        extent allowed by law, the Service is provided "as is" and "as available". We do not
        guarantee that the Service will always be available, uninterrupted, error-free, or that AI
        output will be accurate or fit for a particular purpose.
      </p>
      <p>
        Nothing in these Terms excludes or limits any rights you have as a consumer under UK law
        that cannot lawfully be excluded or limited.
      </p>
    </section>

    <section>
      <h2>11. Liability</h2>
      <p>
        Nothing in these Terms limits our liability for death or personal injury caused by
        negligence, fraud or fraudulent misrepresentation, or any other liability that cannot
        lawfully be limited.
      </p>
      <p>
        Subject to that, to the fullest extent allowed by law:
      </p>
      <ul>
        <li>
          We are not liable for indirect or consequential losses, loss of profits, loss of business,
          loss of goodwill, or loss of data beyond the reasonable costs of restoring data from your
          most recent backup
        </li>
        <li>
          Our total liability to you for any claim arising out of or in connection with the Service
          in any 12-month period is limited to the greater of (a) the amount you paid us for the
          Service in that period, or (b) GBP 100
        </li>
      </ul>
      <p>
        If you use the Service for business purposes, you agree that sideBar is not liable for any
        business losses, and the consumer protections described above do not apply.
      </p>
    </section>

    <section>
      <h2>12. Indemnity</h2>
      <p>
        If you use sideBar for business or commercial purposes, you agree to indemnify sideBar
        against any claims, losses, or costs arising out of your misuse of the Service, your breach
        of these Terms, or content you upload or share through the Service.
      </p>
    </section>

    <section>
      <h2>13. Governing law and disputes</h2>
      <p>
        These Terms are governed by the laws of England and Wales. Disputes will be subject to the
        exclusive jurisdiction of the courts of England and Wales, except that if you are a
        consumer resident in another part of the UK or in the EEA you may also bring proceedings in
        your country of residence.
      </p>
    </section>

    <section>
      <h2>14. Contact</h2>
      <p>
        sideBar Labs Limited, a company registered in England and Wales under company number
        17137829. ICO registration number ZC116277.
      </p>
      <p>
        Support and account questions:
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
