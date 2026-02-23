<script lang="ts">
	import LoadingGlyph from '$lib/components/loading/LoadingGlyph.svelte';
</script>

<svelte:head>
	<title>sideBar</title>
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
		position: relative;
		overflow: hidden;
		width: min(100%, 34rem);
		padding: 2rem;
		border: 1px solid rgb(255 255 255 / 0.5);
		border-radius: 1.25rem;
		background:
			linear-gradient(160deg, rgb(255 255 255 / 0.65) 0%, rgb(255 255 255 / 0.35) 100%),
			var(--color-card);
		backdrop-filter: blur(18px) saturate(140%);
		-webkit-backdrop-filter: blur(18px) saturate(140%);
		box-shadow:
			inset 0 1px 0 rgb(255 255 255 / 0.65),
			0 18px 45px rgb(15 23 42 / 0.16);
		text-align: center;
	}

	.card::before {
		content: '';
		position: absolute;
		inset: 0;
		pointer-events: none;
		background:
			radial-gradient(circle at 15% 0%, rgb(255 255 255 / 0.5) 0, transparent 42%),
			radial-gradient(circle at 100% 100%, rgb(255 255 255 / 0.2) 0, transparent 48%);
	}

	.card::after {
		content: '';
		position: absolute;
		inset: 1px;
		border-radius: calc(1.25rem - 1px);
		pointer-events: none;
		border: 1px solid rgb(255 255 255 / 0.22);
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
		border: 1px solid rgb(255 255 255 / 0.45);
		background:
			linear-gradient(180deg, rgb(255 255 255 / 0.2) 0, transparent 100%), var(--color-primary);
		color: var(--color-primary-foreground);
		font-size: 0.95rem;
		font-weight: 500;
		text-decoration: none;
		backdrop-filter: blur(8px);
		-webkit-backdrop-filter: blur(8px);
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

	:global(.dark) .card {
		border-color: rgb(148 163 184 / 0.24);
		background:
			linear-gradient(165deg, rgb(15 23 42 / 0.54) 0%, rgb(15 23 42 / 0.38) 100%), var(--color-card);
		box-shadow:
			inset 0 1px 0 rgb(255 255 255 / 0.1),
			0 18px 45px rgb(2 6 23 / 0.38);
	}

	:global(.dark) .card::before {
		background:
			radial-gradient(circle at 15% 0%, rgb(148 163 184 / 0.22) 0, transparent 42%),
			radial-gradient(circle at 100% 100%, rgb(59 130 246 / 0.2) 0, transparent 48%);
	}

	:global(.dark) .card::after {
		border-color: rgb(148 163 184 / 0.16);
	}

	:global(.dark) .primary-cta {
		border-color: rgb(148 163 184 / 0.35);
	}
</style>
