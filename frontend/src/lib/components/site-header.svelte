<script lang="ts">
	import { onDestroy, onMount } from "svelte";
	import ModeToggle from "$lib/components/mode-toggle.svelte";
	import ScratchpadPopover from "$lib/components/scratchpad-popover.svelte";

	let currentDate = "";
	let currentTime = "";
	let timeInterval: ReturnType<typeof setInterval> | undefined;

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
	});

	onDestroy(() => {
		if (timeInterval) clearInterval(timeInterval);
	});
</script>

<header class="site-header">
	<div class="brand">
		<span class="brand-mark" aria-hidden="true"></span>
		<div class="brand-text">
			<div class="title">Agent Smith</div>
			<div class="subtitle">Workspace</div>
		</div>
	</div>
	<div class="actions">
		<ScratchpadPopover />
		<ModeToggle />
		<div class="datetime">
			<span class="date">{currentDate}</span>
			<span class="time">{currentTime}</span>
		</div>
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

	.datetime {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 0.1rem;
		margin-left: 1.25rem;
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
