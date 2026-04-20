<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/stores';
	import BrandLockup from '$lib/components/BrandLockup.svelte';
	import ModeToggle from '$lib/components/mode-toggle.svelte';
	import PixelDivider from '$lib/components/PixelDivider.svelte';
	import { Button } from '$lib/components/ui/button';
	import { Folder, FileText, Globe, CheckSquare, MessageSquare, Command } from 'lucide-svelte';
	import { MARKETING_COPY } from '$lib/constants/marketingCopy';
	import { getSupabaseClient } from '$lib/supabase';
	import { logError } from '$lib/utils/errorHandling';

	let email = '';
	let password = '';
	let loading = false;
	let error = '';
	$: loggedOut = $page.url.searchParams.get('loggedOut') === '1';
	$: sessionExpired = $page.url.searchParams.get('reason') === 'session_expired';
	$: redirectTo = (() => {
		const raw = $page.url.searchParams.get('redirectTo');
		if (!raw) return '/';
		try {
			return decodeURIComponent(raw);
		} catch {
			return raw;
		}
	})();

	async function handleLogin(event: SubmitEvent) {
		event.preventDefault();
		loading = true;
		error = '';

		try {
			const supabase = getSupabaseClient();
			const { error: authError } = await supabase.auth.signInWithPassword({
				email,
				password
			});

			if (authError) {
				const message = authError.message || '';
				error = message.toLowerCase().includes('failed to fetch')
					? 'Service unavailable. Please try again later.'
					: authError.message;
				loading = false;
				return;
			}

			await goto(redirectTo, { invalidateAll: true });
		} catch (err) {
			logError('Login failed', err, { scope: 'loginForm.submit' });
			error = 'Service unavailable. Please try again later.';
		} finally {
			loading = false;
		}
	}
</script>

<div class="login-shell">
	<div class="login-container">
		<nav class="login-nav" aria-label="Marketing navigation">
			<PixelDivider position="bottom" />
			<div class="login-nav-inner">
				<a href="https://trysidebar.ai" class="login-brand" aria-label="sideBar home">
					<span class="login-brand-mark" aria-hidden="true">
						<img
							class="login-brand-asset login-brand-asset-light"
							src="/images/logo-light.png"
							alt=""
							width="40"
							height="40"
						/>
						<img
							class="login-brand-asset login-brand-asset-dark"
							src="/images/logo-dark.png"
							alt=""
							width="40"
							height="40"
						/>
					</span>
					<span class="login-brand-name">sideBar</span>
				</a>

				<div class="login-nav-links">
					<a href="https://trysidebar.ai">Home</a>
					<a href="https://trysidebar.ai/about">About</a>
					<a href="https://trysidebar.ai/pricing">Pricing</a>
					<a href="https://docs.trysidebar.ai">Docs</a>
					<ModeToggle />
				</div>
			</div>
		</nav>

		<div class="login-grid">
			<section class="login-intro">
				<h2 class="login-tagline" aria-label={MARKETING_COPY.tagline}>
					<span>Your work.</span>
					<span>Your assistant.</span>
					<span>One place.</span>
				</h2>
				<p class="login-description">{MARKETING_COPY.subtitle}</p>

				<div class="login-features" aria-label="Core sideBar features">
					<div class="feature">
						<MessageSquare size={18} strokeWidth={2} />
						<div class="feature-content">
							<span class="feature-title">Chat</span>
							<span class="feature-desc"
								>Start from what is already in front of you, not a blank box.</span
							>
						</div>
					</div>
					<div class="feature">
						<FileText size={18} strokeWidth={2} />
						<div class="feature-content">
							<span class="feature-title">Notes</span>
							<span class="feature-desc">Write, organise, and keep a scratchpad close at hand.</span
							>
						</div>
					</div>
					<div class="feature">
						<CheckSquare size={18} strokeWidth={2} />
						<div class="feature-content">
							<span class="feature-title">Tasks</span>
							<span class="feature-desc"
								>Keep projects, due dates, and lists in the same workspace.</span
							>
						</div>
					</div>
					<div class="feature">
						<Globe size={18} strokeWidth={2} />
						<div class="feature-content">
							<span class="feature-title">Websites</span>
							<span class="feature-desc"
								>Save pages, read them later, and ask questions across them.</span
							>
						</div>
					</div>
					<div class="feature">
						<Folder size={18} strokeWidth={2} />
						<div class="feature-content">
							<span class="feature-title">Files</span>
							<span class="feature-desc"
								>Bring documents, PDFs, and images into the same context.</span
							>
						</div>
					</div>
					<div class="feature">
						<Command size={18} strokeWidth={2} />
						<div class="feature-content">
							<span class="feature-title">Skills</span>
							<span class="feature-desc"
								>Install useful capabilities as sideBar grows with you.</span
							>
						</div>
					</div>
				</div>
			</section>

			<section class="login-panel">
				<div class="login-panel-header">
					<p class="login-eyebrow">Sign in</p>
					<h1 class="login-wordmark">Welcome back</h1>
				</div>

				{#if loggedOut}
					<div class="login-success">You have been signed out.</div>
				{:else if sessionExpired}
					<div class="login-info">Your session expired. Please sign in again.</div>
				{/if}

				{#if error}
					<div class="login-error">{error}</div>
				{/if}

				<form onsubmit={handleLogin}>
					<label>
						<span>Email</span>
						<input type="email" bind:value={email} autocomplete="email" required />
					</label>
					<label>
						<span>Password</span>
						<input type="password" bind:value={password} autocomplete="current-password" required />
					</label>
					<Button type="submit" disabled={loading} class="w-full">
						{loading ? 'Signing in…' : 'Sign in'}
					</Button>
				</form>
			</section>
		</div>

		<footer class="login-footer" aria-label="Legal links">
			<PixelDivider position="top" />
			<div class="login-footer-inner">
				<div class="login-footer-brand" aria-label="sideBar brand">
					<BrandLockup size="compact" />
				</div>
				<p class="login-footer-copy">
					&copy; {new Date().getFullYear()} sideBar Labs Limited. All rights reserved.
				</p>
				<div class="login-footer-meta">
					<p class="login-footer-registered">
						Registered in England and Wales, company number 17137829.
					</p>
					<p class="login-footer-registered">
						Registered office: 66 Paul Street, London, EC2A 4NA.
					</p>
				</div>
				<div class="login-footer-links">
					<a href="/privacy">Privacy Policy</a>
					<a href="/terms">Terms of Service</a>
					<a href="/eula">EULA</a>
					<a href="mailto:support@trysidebar.ai">Contact</a>
				</div>
			</div>
		</footer>
	</div>
</div>

<style>
	.login-shell {
		min-height: 100vh;
		display: flex;
		width: 100%;
		padding: 0 1.5rem 2rem;
		background: var(--color-background);
	}

	.login-container {
		width: min(100%, 1120px);
		min-height: calc(100dvh - 5rem);
		margin: 0 auto;
		display: flex;
		flex-direction: column;
		gap: 1.5rem;
	}

	.login-nav {
		position: relative;
	}

	.login-nav-inner {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1.5rem;
		min-height: 4.25rem;
	}

	.login-brand {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		color: var(--color-foreground);
		text-decoration: none;
	}

	.login-brand-mark {
		position: relative;
		display: inline-grid;
		place-items: center;
		width: 2.5rem;
		height: 2.5rem;
		flex: 0 0 auto;
	}

	.login-brand-asset {
		grid-area: 1 / 1;
		display: block;
		width: 100%;
		height: 100%;
	}

	.login-brand-asset-dark {
		display: none;
	}

	:global(.dark) .login-brand-asset-light {
		display: none;
	}

	:global(.dark) .login-brand-asset-dark {
		display: block;
	}

	.login-brand-name {
		font-size: 1.375rem;
		font-weight: 700;
		letter-spacing: -0.055em;
		line-height: 0.94;
		white-space: nowrap;
	}

	.login-nav-links {
		display: flex;
		align-items: center;
		gap: 1.25rem;
	}

	.login-nav-links a {
		font-size: 0.95rem;
		font-weight: 500;
		color: var(--color-muted-foreground);
		text-decoration: none;
		transition: color 0.15s ease;
	}

	.login-nav-links a:hover {
		color: var(--color-foreground);
	}

	.login-grid {
		flex: 1 1 auto;
		width: 100%;
		display: grid;
		grid-template-columns: minmax(0, 1.1fr) minmax(22rem, 25rem);
		gap: clamp(2rem, 4vw, 4.5rem);
		align-items: center;
		align-content: center;
	}

	.login-intro {
		display: flex;
		flex-direction: column;
		gap: 1.5rem;
		padding-right: 1rem;
	}

	.login-tagline {
		margin: 0;
		font-size: clamp(2.25rem, 4.8vw, 4.5rem);
		font-weight: 700;
		letter-spacing: -0.055em;
		line-height: 0.94;
		color: var(--color-foreground);
	}

	.login-tagline span {
		display: block;
	}

	.login-description {
		margin: 0;
		max-width: 34rem;
		font-size: 1.05rem;
		line-height: 1.55;
		color: var(--color-muted-foreground);
		text-wrap: balance;
	}

	.login-features {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		column-gap: 1.5rem;
		row-gap: 0;
		border-top: 1px solid var(--color-border);
	}

	.feature {
		display: flex;
		align-items: flex-start;
		gap: 0.75rem;
		padding: 1rem 0;
		border-bottom: 1px solid var(--color-border);
	}

	.feature :global(svg) {
		flex-shrink: 0;
		margin-top: 0.2rem;
		color: var(--color-foreground);
	}

	.feature-content {
		display: flex;
		flex-direction: column;
		gap: 0.125rem;
		min-width: 0;
	}

	.feature-title {
		font-size: 0.95rem;
		font-weight: 600;
		color: var(--color-foreground);
	}

	.feature-desc {
		font-size: 0.875rem;
		line-height: 1.5;
		color: var(--color-muted-foreground);
	}

	.login-panel {
		padding: 2rem;
		border-radius: 1.25rem;
		border: 1px solid var(--color-border);
		background: var(--surface);
		display: flex;
		flex-direction: column;
		gap: 1.25rem;
	}

	.login-panel-header {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 0.5rem;
	}

	.login-eyebrow {
		margin: 0;
		font-size: 0.75rem;
		font-weight: 600;
		letter-spacing: 0.12em;
		text-transform: uppercase;
		color: var(--color-muted-foreground);
	}

	.login-wordmark {
		margin: 0;
		font-size: 2rem;
		font-weight: 650;
		letter-spacing: -0.04em;
		line-height: 0.96;
		color: var(--color-foreground);
	}

	.login-success,
	.login-info,
	.login-error {
		padding: 0.875rem 1rem;
		border-radius: 0.875rem;
		font-size: 0.875rem;
		line-height: 1.5;
	}

	.login-success,
	.login-info {
		background: var(--color-muted);
		border: 1px solid var(--color-border);
		color: var(--color-foreground);
	}

	.login-error {
		background: color-mix(in srgb, var(--color-destructive) 10%, transparent);
		border: 1px solid color-mix(in srgb, var(--color-destructive) 45%, transparent);
		color: var(--color-destructive);
	}

	form {
		display: flex;
		flex-direction: column;
		gap: 0.875rem;
	}

	label {
		display: flex;
		flex-direction: column;
		gap: 0.45rem;
	}

	label span {
		font-size: 0.875rem;
		font-weight: 500;
		color: var(--color-foreground);
	}

	input {
		width: 100%;
		padding: 0.85rem 0.95rem;
		border: 1px solid var(--color-input);
		border-radius: 0.875rem;
		background: var(--color-background);
		color: var(--color-foreground);
		font-size: 0.95rem;
		transition:
			border-color 0.15s ease,
			box-shadow 0.15s ease;
	}

	input:focus {
		outline: none;
		border-color: var(--color-ring);
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--color-ring) 20%, transparent);
	}

	input::placeholder {
		color: var(--color-muted-foreground);
	}

	:global(.login-panel button.w-full) {
		margin-top: 0.25rem;
	}

	.login-footer {
		position: relative;
		display: flex;
		padding-top: 1.25rem;
		margin-top: auto;
	}

	.login-footer-inner {
		width: 100%;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 0.75rem;
		padding-top: 1.25rem;
		text-align: center;
	}

	.login-footer-brand {
		display: inline-flex;
		align-items: center;
		justify-content: center;
	}

	.login-footer-copy,
	.login-footer-registered {
		margin: 0;
		max-width: 40rem;
		font-size: 0.8125rem;
		line-height: 1.6;
		color: var(--color-muted-foreground);
	}

	.login-footer-meta {
		display: grid;
		gap: 0.125rem;
	}

	.login-footer-links {
		display: flex;
		flex-wrap: wrap;
		justify-content: center;
		gap: 0.75rem 1.25rem;
		font-size: 0.8125rem;
		color: var(--color-muted-foreground);
	}

	.login-footer-links a {
		color: inherit;
		text-decoration: none;
	}

	.login-footer-links a:hover {
		color: var(--color-foreground);
	}

	@media (max-width: 900px) {
		.login-shell {
			padding: 0 1rem 1.5rem;
		}

		.login-container {
			min-height: calc(100dvh - 3rem);
		}

		.login-nav-inner {
			padding: 0.75rem 0;
			align-items: flex-start;
			flex-wrap: wrap;
		}

		.login-nav-links {
			width: 100%;
			justify-content: space-between;
			gap: 0.75rem;
			flex-wrap: wrap;
		}

		.login-nav-links a {
			font-size: 0.9rem;
		}

		.login-grid {
			grid-template-columns: 1fr;
			gap: 2rem;
		}

		.login-intro {
			padding-right: 0;
		}

		.login-features {
			grid-template-columns: 1fr;
		}
	}

	@media (max-width: 640px) {
		.login-panel {
			padding: 1.5rem;
		}

		.login-tagline {
			max-width: none;
		}

		.login-footer {
			padding-top: 1rem;
		}

		.login-footer-inner {
			padding-top: 1rem;
		}
	}
</style>
