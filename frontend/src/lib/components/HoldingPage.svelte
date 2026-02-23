<script lang="ts">
	import LoadingGlyph from '$lib/components/loading/LoadingGlyph.svelte';
</script>

<svelte:head>
	<title>trsidebar.ai - Launching Soon</title>
	<link rel="icon" type="image/x-icon" href="/favicon.ico" />
	<link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png" />
	<link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png" />
	<link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png" />
</svelte:head>

<div class="holding-page">
	<main class="card">
		<div class="logo" aria-label="sideBar logo">
			<LoadingGlyph
				size={96}
				lightSrc="/images/loading-light-128.gif"
				darkSrc="/images/loading-dark-128.gif"
			/>
		</div>
		<h1><span>sideBar</span><span>is launching soon</span></h1>
		<p class="copy">
			We are putting the finishing touches on the product experience. If you already have access,
			you can sign in now.
		</p>
		<a class="primary-cta" href="https://app.trysidebar.ai">Open App</a>
	</main>
</div>

<style>
	.holding-page {
		min-height: 100dvh;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 1.5rem;
		background:
			radial-gradient(circle at 10% 10%, rgb(59 130 246 / 0.12) 0, transparent 45%),
			radial-gradient(circle at 85% 20%, rgb(99 102 241 / 0.12) 0, transparent 40%),
			var(--color-background);
	}

	.card {
		width: min(100%, 34rem);
		padding: 2rem;
		border: 1px solid var(--color-border);
		border-radius: 1rem;
		background: var(--color-card);
		box-shadow: 0 10px 30px rgb(15 23 42 / 0.14);
		text-align: center;
	}

	.logo {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		margin-bottom: 0.75rem;
	}

	h1 {
		margin: 0.3rem 0 0.75rem;
		font-size: clamp(1.6rem, 2.3vw, 2rem);
		font-weight: 600;
		line-height: 1.2;
		letter-spacing: -0.01em;
		color: var(--color-card-foreground);
	}

	h1 span {
		display: block;
	}

	.copy {
		margin: 0 0 1.4rem;
		font-size: 1rem;
		line-height: 1.55;
		color: var(--color-muted-foreground);
	}

	.primary-cta {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-height: 2.75rem;
		padding: 0 1.15rem;
		border-radius: 999px;
		background: var(--color-primary);
		color: var(--color-primary-foreground);
		font-size: 0.95rem;
		font-weight: 500;
		text-decoration: none;
	}

	.primary-cta:hover {
		filter: brightness(0.93);
	}

	:global(.dark) .holding-page {
		background:
			radial-gradient(circle at 10% 10%, rgb(59 130 246 / 0.18) 0, transparent 45%),
			radial-gradient(circle at 85% 20%, rgb(99 102 241 / 0.18) 0, transparent 40%),
			var(--color-background);
	}
</style>
