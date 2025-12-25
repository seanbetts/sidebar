<script lang="ts">
	import { onDestroy, onMount } from "svelte";
	import ModeToggle from "$lib/components/mode-toggle.svelte";
	import ScratchpadPopover from "$lib/components/scratchpad-popover.svelte";

	let currentDate = "";
	let currentTime = "";
	let liveLocation = "";
	let timeInterval: ReturnType<typeof setInterval> | undefined;
	const locationCacheKey = "sidebar.liveLocation";
	const locationCacheTimeKey = "sidebar.liveLocationTs";
	const locationCacheTtlMs = 30 * 60 * 1000;

	function updateDateTime() {
		const now = new Date();
		currentDate = new Intl.DateTimeFormat(undefined, {
			weekday: "short",
			month: "short",
			day: "2-digit"
		}).format(now);
		currentTime = new Intl.DateTimeFormat(undefined, {
			hour: "2-digit",
			minute: "2-digit"
		}).format(now);
	}

	onMount(() => {
		updateDateTime();
		timeInterval = setInterval(updateDateTime, 60_000);
		loadLocation();
	});

	onDestroy(() => {
		if (timeInterval) clearInterval(timeInterval);
	});

	async function loadLocation() {
		if (typeof window === "undefined" || !navigator.geolocation) {
			return;
		}

		const cachedLabel = localStorage.getItem(locationCacheKey);
		const cachedTime = localStorage.getItem(locationCacheTimeKey);
		if (cachedLabel && cachedTime) {
			const age = Date.now() - Number(cachedTime);
			if (!Number.isNaN(age) && age < locationCacheTtlMs) {
				liveLocation = cachedLabel;
				return;
			}
		}

		navigator.geolocation.getCurrentPosition(
			async (position) => {
				try {
					const { latitude, longitude } = position.coords;
					const response = await fetch(
						`/api/places/reverse?lat=${encodeURIComponent(latitude)}&lng=${encodeURIComponent(longitude)}`
					);
					if (!response.ok) {
						return;
					}
					const data = await response.json();
					const label = data?.label;
					if (label) {
						liveLocation = label;
						localStorage.setItem(locationCacheKey, label);
						localStorage.setItem(locationCacheTimeKey, Date.now().toString());
					}
				} catch (error) {
					console.error("Failed to load live location:", error);
				}
			},
			() => {
				// User denied or unavailable; do nothing.
			},
			{ enableHighAccuracy: false, maximumAge: locationCacheTtlMs, timeout: 8000 }
		);
	}
</script>

<header class="site-header">
	<div class="brand">
		<img src="/images/logo.svg" alt="sideBar" class="brand-logo" />
		<span class="brand-mark" aria-hidden="true"></span>
		<div class="brand-text">
			<div class="title">sideBar</div>
			<div class="subtitle">Workspace</div>
		</div>
	</div>
	<div class="actions">
		<div class="datetime-group">
			{#if liveLocation}
				<span class="location">{liveLocation}</span>
			{/if}
			<div class="datetime">
				<span class="date">{currentDate}</span>
				<span class="time">{currentTime}</span>
			</div>
		</div>
		<ScratchpadPopover />
		<ModeToggle />
	</div>
</header>

<style>
	:global(:root) {
		--site-header-height: 64px;
	}

	.site-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
		height: var(--site-header-height);
		padding: 0.75rem 1.5rem;
		border-bottom: 1px solid var(--color-border);
		background: linear-gradient(90deg, rgba(0, 0, 0, 0.04), rgba(0, 0, 0, 0));
	}

	.brand {
		display: flex;
		align-items: center;
		gap: 0.75rem;
	}

	.brand-logo {
		height: 2rem;
		width: auto;
	}

	:global(.dark) .brand-logo {
		filter: invert(1);
	}

	.brand-mark {
		height: 2.25rem;
		width: 0.25rem;
		border-radius: 999px;
		background-color: var(--color-primary);
	}

	.brand-text {
		display: flex;
		flex-direction: column;
	}

	.title {
		font-size: 1.125rem;
		font-weight: 700;
		letter-spacing: 0.01em;
		color: var(--color-foreground);
	}

	.subtitle {
		font-size: 0.75rem;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--color-muted-foreground);
	}

	.actions {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}

	.datetime-group {
		display: flex;
		align-items: center;
		gap: 1.25rem;
		margin-right: 1.25rem;
	}

	.datetime {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 0.1rem;
	}

	.location {
		font-size: 0.75rem;
		letter-spacing: 0.02em;
		text-transform: uppercase;
		color: var(--color-muted-foreground);
		white-space: nowrap;
	}

	.date {
		font-size: 0.75rem;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--color-muted-foreground);
	}

	.time {
		font-size: 0.95rem;
		font-weight: 600;
		color: var(--color-foreground);
	}
</style>
