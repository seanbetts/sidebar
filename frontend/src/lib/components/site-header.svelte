<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import { toast } from 'svelte-sonner';
	import { useSiteHeaderData } from '$lib/hooks/useSiteHeaderData';
	import { useThingsBridgeStatus } from '$lib/hooks/useThingsBridgeStatus';
	import { get } from 'svelte/store';
	import { websitesStore, type WebsiteTranscriptEntry } from '$lib/stores/websites';
	import { transcriptStatusStore } from '$lib/stores/transcript-status';
	import ModeToggle from '$lib/components/mode-toggle.svelte';
	import ScratchpadPopover from '$lib/components/scratchpad-popover.svelte';
	import { Button } from '$lib/components/ui/button';
	import { Tooltip, TooltipContent, TooltipTrigger } from '$lib/components/ui/tooltip';
	import { layoutStore } from '$lib/stores/layout';
	import { canShowTooltips } from '$lib/utils/tooltip';
	import { resolveWeatherIcon } from '$lib/utils/weatherIcons';
	import { ArrowLeftRight } from 'lucide-svelte';

	const siteHeaderData = useSiteHeaderData();
	let currentDate = '';
	let currentTime = '';
	let liveLocation = '';
	let weatherTemp = '';
	let weatherCode: number | null = null;
	let weatherIsDay: number | null = null;
	const thingsStatus = useThingsBridgeStatus();
	let bridgeStatus: 'loading' | 'online' | 'offline' = 'loading';
	let bridgeSeenAt: string | null = null;
	let transcriptStatus: 'processing' | null = null;
	let transcriptLabel = '';
	let transcriptPollingId: ReturnType<typeof setInterval> | null = null;
	let transcriptPollingKey: string | null = null;
	let transcriptPollingInFlight = false;
	let pendingTranscript: {
		websiteId: string;
		videoId: string;
		entry: WebsiteTranscriptEntry;
	} | null = null;
	let tooltipsEnabled = false;

	$: ({ currentDate, currentTime, liveLocation, weatherTemp, weatherCode, weatherIsDay } =
		$siteHeaderData);
	$: ({ status: bridgeStatus, lastSeenAt: bridgeSeenAt } = $thingsStatus);
	onMount(() => {
		tooltipsEnabled = canShowTooltips();
	});
	const isTranscriptPending = (status?: string) =>
		status === 'queued' || status === 'processing' || status === 'retrying';

	const isTranscriptFailed = (status?: string) => status === 'failed' || status === 'canceled';

	const getTranscriptCandidates = () => {
		const active = $websitesStore.active;
		const candidates: { websiteId: string; videoId: string; entry: WebsiteTranscriptEntry }[] = [];
		if (active?.youtube_transcripts && Object.keys(active.youtube_transcripts).length > 0) {
			for (const [videoId, entry] of Object.entries(active.youtube_transcripts)) {
				candidates.push({ websiteId: active.id, videoId, entry });
			}
		}
		for (const item of $websitesStore.items) {
			if (active && item.id === active.id) continue;
			if (!item.youtube_transcripts) continue;
			for (const [videoId, entry] of Object.entries(item.youtube_transcripts)) {
				candidates.push({ websiteId: item.id, videoId, entry });
			}
		}
		return candidates;
	};

	const pickLatest = (
		candidates: { websiteId: string; videoId: string; entry: WebsiteTranscriptEntry }[]
	) =>
		candidates
			.map((candidate) => ({
				...candidate,
				updatedAt: candidate.entry.updated_at ? new Date(candidate.entry.updated_at).getTime() : 0
			}))
			.sort((a, b) => b.updatedAt - a.updatedAt)[0];

	$: {
		const currentJob = $transcriptStatusStore;
		if (currentJob) {
			transcriptStatus = 'processing';
			transcriptLabel = 'Transcribing';
			pendingTranscript = {
				websiteId: currentJob.websiteId,
				videoId: currentJob.videoId,
				entry: { file_id: currentJob.fileId, status: 'processing' }
			};
		} else {
			const candidates = getTranscriptCandidates();
			const pending = candidates.filter((item) => isTranscriptPending(item.entry.status));
			if (pending.length > 0) {
				const latest = pickLatest(pending);
				transcriptStatus = 'processing';
				transcriptLabel = 'Transcribing';
				pendingTranscript = latest;
			} else {
				transcriptStatus = null;
				transcriptLabel = '';
				pendingTranscript = null;
			}
		}
	}

	function stopTranscriptPolling() {
		if (transcriptPollingId) {
			clearInterval(transcriptPollingId);
			transcriptPollingId = null;
		}
		transcriptPollingKey = null;
		transcriptPollingInFlight = false;
	}

	function getTranscriptEntry(websiteId: string, videoId: string): WebsiteTranscriptEntry | null {
		const state = get(websitesStore);
		const activeEntry =
			state.active?.id === websiteId ? state.active?.youtube_transcripts?.[videoId] : null;
		if (activeEntry) return activeEntry;
		const item = state.items.find((entry) => entry.id === websiteId);
		return item?.youtube_transcripts?.[videoId] ?? null;
	}

	async function pollTranscriptJob(
		fileId: string | undefined,
		websiteId: string,
		videoId: string
	): Promise<void> {
		const pollingKey = `${websiteId}:${videoId}`;
		if (transcriptPollingKey === pollingKey) return;
		stopTranscriptPolling();
		transcriptPollingKey = pollingKey;
		transcriptPollingId = setInterval(async () => {
			if (transcriptPollingInFlight) return;
			transcriptPollingInFlight = true;
			try {
				if ($websitesStore.active?.id === websiteId) {
					await websitesStore.loadById(websiteId);
				} else {
					await websitesStore.refreshItem(websiteId);
				}
				const entry = getTranscriptEntry(websiteId, videoId);
				const status = entry?.status;
				if (!status) return;
				if (status !== 'ready' && status !== 'failed' && status !== 'canceled') {
					websitesStore.setTranscriptEntryLocal(websiteId, videoId, {
						status: 'processing',
						file_id: fileId,
						updated_at: new Date().toISOString()
					});
				}
				if (status === 'ready') {
					stopTranscriptPolling();
					websitesStore.setTranscriptEntryLocal(websiteId, videoId, {
						status: 'ready',
						file_id: fileId,
						updated_at: new Date().toISOString()
					});
					if ($websitesStore.active?.id === websiteId) {
						await websitesStore.loadById(websiteId);
					}
					toast.success('Transcript ready', {
						description: 'Transcript appended to the website.'
					});
					transcriptStatus = null;
					transcriptLabel = '';
					transcriptStatusStore.set(null);
					return;
				}
				if (status === 'failed' || status === 'canceled') {
					stopTranscriptPolling();
					websitesStore.setTranscriptEntryLocal(websiteId, videoId, {
						status: 'failed',
						file_id: fileId,
						updated_at: new Date().toISOString()
					});
					toast.error('Transcript failed', { description: 'Please try again.' });
					transcriptStatus = null;
					transcriptLabel = '';
					transcriptStatusStore.set(null);
				}
			} catch (error) {
				stopTranscriptPolling();
			} finally {
				transcriptPollingInFlight = false;
			}
		}, 5000);
	}

	$: if (pendingTranscript) {
		pollTranscriptJob(
			pendingTranscript.entry.file_id,
			pendingTranscript.websiteId,
			pendingTranscript.videoId
		);
	} else {
		stopTranscriptPolling();
	}

	onDestroy(() => {
		stopTranscriptPolling();
	});

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
		<div class="status-stack">
			<div
				class="things-status"
				aria-live="polite"
				title={bridgeSeenAt ? `Last seen ${bridgeSeenAt}` : ''}
			>
				<span class="label">Bridge</span>
				<span
					class="dot"
					class:online={bridgeStatus === 'online'}
					class:offline={bridgeStatus === 'offline'}
					class:loading={bridgeStatus === 'loading'}
				></span>
			</div>
			{#if transcriptStatus}
				<div class="things-status transcript-status" data-status={transcriptStatus}>
					<span class="label">{transcriptLabel}</span>
					<span class="dot"></span>
				</div>
			{/if}
		</div>
	</div>
	<div class="actions">
		<div class="datetime-group">
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
		<Tooltip disabled={!tooltipsEnabled}>
			<TooltipTrigger>
				{#snippet child({ props })}
					<Button
						size="icon"
						variant="outline"
						{...props}
						onclick={(event) => {
							props.onclick?.(event);
							handleLayoutSwap(event);
						}}
						aria-label="Swap layout"
						class="swap-button border-border"
					>
						<ArrowLeftRight size={20} />
					</Button>
				{/snippet}
			</TooltipTrigger>
			<TooltipContent side="bottom">Swap chat and workspace positions</TooltipContent>
		</Tooltip>
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

	.status-stack {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 0.25rem;
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

	.transcript-status[data-status='processing'] .dot {
		background: #d99a2b;
		animation: transcript-pulse 1.4s ease-in-out infinite;
	}

	@keyframes transcript-pulse {
		0% {
			transform: scale(1);
			opacity: 0.6;
		}
		50% {
			transform: scale(1.2);
			opacity: 1;
		}
		100% {
			transform: scale(1);
			opacity: 0.6;
		}
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
		grid-template-columns: auto auto;
		row-gap: 0.1rem;
		column-gap: 0.8rem;
		margin-right: 1.25rem;
		align-items: center;
	}

	.things-status {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.2rem 0.5rem;
		margin-left: 0.6rem;
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

	.things-status .dot.loading {
		background: #f59e0b;
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
