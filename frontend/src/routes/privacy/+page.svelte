<svelte:head>
	<title>Privacy Policy | sideBar</title>
	<meta
		name="description"
		content="Privacy Policy for sideBar by trysidebar.ai, including data collection, usage, retention, and user rights."
	/>
</svelte:head>

<div class="privacy-page">
	<main class="privacy-content">
		<header>
			<h1>Privacy Policy</h1>
			<p class="meta">Last updated: February 28, 2026</p>
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
				<li>Prompts, chat history, notes, files, and saved website content</li>
				<li>Workspace metadata (such as titles, tags, and organization choices)</li>
			</ul>
			<h3>Technical and Usage Data</h3>
			<ul>
				<li>Device, browser, and app version details</li>
				<li>Operational logs, error diagnostics, and performance telemetry</li>
				<li>IP address and approximate location derived from network requests</li>
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
				To provide sideBar, we use infrastructure and service providers that may process data on our
				behalf, including hosting, authentication, storage, analytics, and AI model providers.
			</p>
			<p>
				Depending on your configuration, this can include providers such as Supabase, Cloudflare R2,
				Vercel, Sentry, Anthropic, OpenAI, and Google. We require vendors to handle data under
				contractual and security controls appropriate for their role.
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
			<h2>9. Children’s Privacy</h2>
			<p>
				sideBar is not directed to children under 13 (or the applicable minimum age in your region).
				We do not knowingly collect personal data from children. If you believe a child provided
				data, contact us and we will investigate and take appropriate action.
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
	</main>
</div>

<style>
	.privacy-page {
		height: 100dvh;
		overflow-y: auto;
		padding: 2rem 1rem 2.5rem;
		background:
			radial-gradient(circle at 8% 6%, rgb(15 23 42 / 0.08) 0, transparent 38%),
			radial-gradient(circle at 90% 4%, rgb(14 116 144 / 0.08) 0, transparent 34%),
			var(--color-background);
	}

	.privacy-content {
		max-width: 820px;
		margin: 0 auto;
		padding: 1.5rem;
		border-radius: 16px;
		border: 1px solid var(--color-border);
		background: color-mix(in oklab, var(--color-card) 94%, transparent);
		color: var(--color-card-foreground);
		line-height: 1.6;
	}

	h1 {
		margin: 0;
		font-size: clamp(1.65rem, 3vw, 2.25rem);
		line-height: 1.2;
		letter-spacing: -0.01em;
	}

	.meta {
		margin: 0.5rem 0 0;
		color: var(--color-muted-foreground);
		font-size: 0.95rem;
	}

	section {
		margin-top: 1.5rem;
	}

	h2 {
		margin: 0 0 0.5rem;
		font-size: 1.2rem;
	}

	h3 {
		margin: 0.9rem 0 0.35rem;
		font-size: 1rem;
	}

	p {
		margin: 0.6rem 0;
	}

	ul {
		margin: 0.4rem 0 0.6rem;
		padding-left: 1.25rem;
	}

	li + li {
		margin-top: 0.3rem;
	}

	a {
		color: var(--color-primary);
	}

	@media (max-width: 640px) {
		.privacy-page {
			padding: 1rem 0.75rem 1.5rem;
		}

		.privacy-content {
			padding: 1rem;
		}
	}
</style>
