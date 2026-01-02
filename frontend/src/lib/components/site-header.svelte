<script lang="ts">
	import { useSiteHeaderData } from "$lib/hooks/useSiteHeaderData";
	import { useThingsBridgeStatus } from "$lib/hooks/useThingsBridgeStatus";
	import ModeToggle from "$lib/components/mode-toggle.svelte";
	import ScratchpadPopover from "$lib/components/scratchpad-popover.svelte";
	import { Button } from "$lib/components/ui/button";
	import { layoutStore } from "$lib/stores/layout";
	import { resolveWeatherIcon } from "$lib/utils/weatherIcons";
	import { ArrowLeftRight } from "lucide-svelte";

	const siteHeaderData = useSiteHeaderData();
	let currentDate = "";
	let currentTime = "";
	let liveLocation = "";
	let weatherTemp = "";
	let weatherCode: number | null = null;
	let weatherIsDay: number | null = null;
	const thingsStatus = useThingsBridgeStatus();
	let bridgeStatus: "loading" | "online" | "offline" = "loading";
	let bridgeSeenAt: string | null = null;

	$: ({ currentDate, currentTime, liveLocation, weatherTemp, weatherCode, weatherIsDay } = $siteHeaderData);
	$: ({ status: bridgeStatus, lastSeenAt: bridgeSeenAt } = $thingsStatus);

	function handleLayoutSwap() {
		layoutStore.toggleMode();
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
			<div
				class="things-status"
				aria-live="polite"
				title={bridgeSeenAt ? `Last seen ${bridgeSeenAt}` : ""}
			>
				<span
					class="dot"
					class:online={bridgeStatus === "online"}
					class:offline={bridgeStatus === "offline"}
				></span>
				<span class="label">Bridge</span>
			</div>
			<span class="date">{currentDate}</span>
			<span class="time">{currentTime}</span>
			{#if liveLocation}
				<span class="location">{liveLocation}</span>
			{/if}
			{#if weatherTemp}
				<span class="weather">
					<svelte:component this={resolveWeatherIcon(weatherCode, weatherIsDay)} size={16} />
					<span class="weather-temp">{weatherTemp}</span>
				</span>
			{/if}
		</div>
		<Button
			size="icon"
			variant="outline"
			onclick={handleLayoutSwap}
			aria-label="Swap layout"
			title="Swap chat and workspace positions"
			class="swap-button border-border"
		>
			<ArrowLeftRight size={20} />
		</Button>
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
		display: grid;
		grid-template-columns: auto auto auto;
		row-gap: 0.1rem;
		column-gap: 0.8rem;
		margin-right: 1.25rem;
		align-items: center;
	}

	.things-status {
		grid-row: 1 / span 2;
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		padding: 0.2rem 0.5rem;
		border-radius: 999px;
		border: 1px solid var(--color-border);
		color: var(--color-muted-foreground);
		font-size: 0.7rem;
		letter-spacing: 0.04em;
		text-transform: uppercase;
	}

	.things-status .dot {
		width: 6px;
		height: 6px;
		border-radius: 999px;
		background: var(--color-muted-foreground);
	}

	.things-status .dot.online {
		background: #22c55e;
	}

	.things-status .dot.offline {
		background: #ef4444;
	}

	.datetime-group .date {
		text-align: right;
	}

	.datetime-group .location {
		text-align: right;
	}

	.datetime-group .time {
		text-align: right;
	}

	.datetime-group .weather {
		justify-self: end;
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
		gap: 0.4rem;
		color: var(--color-foreground);
		font-size: 0.95rem;
		font-weight: 600;
	}

	.weather :global(svg) {
		width: 14px;
		height: 14px;
	}

	:global(.swap-button) {
		color: var(--color-muted-foreground);
		transition: color 0.2s ease;
	}

	:global(.swap-button:hover) {
		color: var(--color-foreground);
	}

	@media (max-width: 900px) {
		:global(.swap-button) {
			display: none;
		}
		.things-status {
			display: none;
		}
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
