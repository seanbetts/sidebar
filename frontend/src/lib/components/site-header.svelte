<script lang="ts">
	import { useSiteHeaderData } from "$lib/hooks/useSiteHeaderData";
	import ModeToggle from "$lib/components/mode-toggle.svelte";
	import ScratchpadPopover from "$lib/components/scratchpad-popover.svelte";
	import { resolveWeatherIcon } from "$lib/utils/weatherIcons";

	const siteHeaderData = useSiteHeaderData();
	let currentDate = "";
	let currentTime = "";
	let liveLocation = "";
	let weatherTemp = "";
	let weatherCode: number | null = null;
	let weatherIsDay: number | null = null;

	$: ({ currentDate, currentTime, liveLocation, weatherTemp, weatherCode, weatherIsDay } = $siteHeaderData);
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
			{#if weatherTemp || liveLocation}
				<div class="weather-location">
					{#if weatherTemp}
						<span class="weather">
							<svelte:component this={resolveWeatherIcon(weatherCode, weatherIsDay)} size={16} />
							<span class="weather-temp">{weatherTemp}</span>
						</span>
					{/if}
					{#if liveLocation}
						<span class="location">{liveLocation}</span>
					{/if}
				</div>
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

	.weather-location {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 0.15rem;
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

	.weather {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		color: var(--color-foreground);
		font-size: 0.95rem;
		font-weight: 600;
	}

	.weather :global(svg) {
		width: 16px;
		height: 16px;
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
