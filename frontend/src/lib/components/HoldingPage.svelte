<script lang="ts">
	import { onMount } from 'svelte';

	let mounted = false;

	onMount(() => {
		mounted = true;
	});
</script>

<svelte:head>
	<title>sideBar - Coming Soon</title>
	<link rel="icon" type="image/x-icon" href="/favicon.ico" />
	<link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png" />
	<link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png" />
	<link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png" />
</svelte:head>

<div class="holding-page" class:mounted>
	<div class="content">
		<div class="logo">
			<div class="logo-icon">
				<img src="/images/logo.svg" alt="sideBar" />
			</div>
			<h1>sideBar</h1>
		</div>

		<div class="message">
			<h2>I'm preparing something special</h2>
			<p>
				I'm working hard to bring you a powerful new way to organise your thoughts, notes, and
				conversations.
			</p>
		</div>

		<div class="features">
			<div class="feature">
				<svg
					width="24"
					height="24"
					viewBox="0 0 24 24"
					fill="none"
					stroke="currentColor"
					stroke-width="2"
					stroke-linecap="round"
					stroke-linejoin="round"
				>
					<path d="M12 20h9" />
					<path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z" />
				</svg>
				<span>Rich markdown editing</span>
			</div>
			<div class="feature">
				<svg
					width="24"
					height="24"
					viewBox="0 0 24 24"
					fill="none"
					stroke="currentColor"
					stroke-width="2"
					stroke-linecap="round"
					stroke-linejoin="round"
				>
					<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
				</svg>
				<span>AI-powered conversations</span>
			</div>
			<div class="feature">
				<svg
					width="24"
					height="24"
					viewBox="0 0 24 24"
					fill="none"
					stroke="currentColor"
					stroke-width="2"
					stroke-linecap="round"
					stroke-linejoin="round"
				>
					<path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z" />
					<path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z" />
				</svg>
				<span>Knowledge management</span>
			</div>
		</div>

		<div class="footer">
			<p>Check back soon</p>
		</div>
	</div>
</div>

<style>
	.holding-page {
		min-height: 100vh;
		width: 100vw;
		display: flex;
		align-items: center;
		justify-content: center;
		background: #ffffff;
		padding: 2rem;
		opacity: 0;
		transition: opacity 0.6s ease-out;
	}

	.holding-page.mounted {
		opacity: 1;
	}

	.content {
		max-width: 600px;
		text-align: center;
		color: #000000;
	}

	.logo {
		margin-bottom: 2rem;
	}

	.logo-icon {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 120px;
		height: 120px;
		margin-bottom: 0;
	}

	.logo-icon img {
		width: 100%;
		height: 100%;
	}

	h1 {
		font-size: 3rem;
		font-weight: 700;
		margin: 0;
		line-height: 1;
		letter-spacing: -0.02em;
	}

	.message {
		margin-bottom: 3rem;
	}

	h2 {
		font-size: 1.5rem;
		font-weight: 600;
		margin: 0 0 1rem 0;
		color: #000000;
	}

	.message p {
		font-size: 1.125rem;
		line-height: 1.7;
		color: #333333;
		margin: 0;
	}

	.features {
		display: flex;
		flex-direction: column;
		gap: 1rem;
		margin-bottom: 3rem;
	}

	.feature {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 0.75rem;
		padding: 1rem 1.5rem;
		background: #f5f5f5;
		border-radius: 12px;
		border: 1px solid #e0e0e0;
		transition:
			transform 0.2s ease,
			background 0.2s ease;
	}

	.feature:hover {
		transform: translateY(-2px);
		background: #eeeeee;
	}

	.feature svg {
		flex-shrink: 0;
		color: #000000;
	}

	.feature span {
		font-size: 1rem;
		font-weight: 500;
		color: #000000;
	}

	.footer {
		margin-top: 3rem;
		padding-top: 2rem;
		border-top: 1px solid #e0e0e0;
	}

	.footer p {
		font-size: 1.125rem;
		font-weight: 600;
		color: #000000;
		margin: 0;
	}

	@media (min-width: 640px) {
		.features {
			flex-direction: row;
		}

		.feature {
			flex: 1;
			flex-direction: column;
			gap: 0.5rem;
			padding: 1.5rem 1rem;
		}

		.feature span {
			font-size: 0.875rem;
		}
	}
</style>
