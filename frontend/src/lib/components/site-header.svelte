<script lang="ts">
	import { onDestroy } from "svelte";
	import { toast } from "svelte-sonner";
	import { useSiteHeaderData } from "$lib/hooks/useSiteHeaderData";
	import { useThingsBridgeStatus } from "$lib/hooks/useThingsBridgeStatus";
	import { ingestionAPI, websitesAPI } from "$lib/services/api";
	import { websitesStore, type WebsiteTranscriptEntry } from "$lib/stores/websites";
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
	let transcriptStatus: "processing" | "ready" | "failed" | null = null;
	let transcriptLabel = "";
	let transcriptPollingId: ReturnType<typeof setInterval> | null = null;
	let transcriptPollingFileId: string | null = null;
	let pendingTranscript:
		| { websiteId: string; videoId: string; entry: WebsiteTranscriptEntry }
		| null = null;

	$: ({ currentDate, currentTime, liveLocation, weatherTemp, weatherCode, weatherIsDay } = $siteHeaderData);
	$: ({ status: bridgeStatus, lastSeenAt: bridgeSeenAt } = $thingsStatus);
	const isTranscriptPending = (status?: string) =>
		status === "queued" || status === "processing" || status === "retrying";

	const isTranscriptFailed = (status?: string) =>
		status === "failed" || status === "canceled";

	const getTranscriptCandidates = () => {
		const active = $websitesStore.active;
		const candidates: { websiteId: string; videoId: string; entry: WebsiteTranscriptEntry }[] = [];
		if (active?.youtube_transcripts) {
			for (const [videoId, entry] of Object.entries(active.youtube_transcripts)) {
				candidates.push({ websiteId: active.id, videoId, entry });
			}
			return candidates;
		}
		for (const item of $websitesStore.items) {
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
		const candidates = getTranscriptCandidates();
		const pending = candidates.filter((item) => isTranscriptPending(item.entry.status));
		const failed = candidates.filter((item) => isTranscriptFailed(item.entry.status));
		const ready = candidates.filter((item) => item.entry.status === "ready");

		if (pending.length > 0) {
			transcriptStatus = "processing";
			transcriptLabel = "Transcribing";
			pendingTranscript = pickLatest(pending);
		} else if (failed.length > 0) {
			transcriptStatus = "failed";
			transcriptLabel = "Transcript Failed";
			pendingTranscript = null;
		} else if (ready.length > 0) {
			transcriptStatus = "ready";
			transcriptLabel = "Transcript Ready";
			pendingTranscript = null;
		} else {
			transcriptStatus = null;
			transcriptLabel = "";
			pendingTranscript = null;
		}
	}

	function stopTranscriptPolling() {
		if (transcriptPollingId) {
			clearInterval(transcriptPollingId);
			transcriptPollingId = null;
		}
		transcriptPollingFileId = null;
	}

	async function retryTranscript(websiteId: string, videoId: string) {
		const url = `https://www.youtube.com/watch?v=${videoId}`;
		try {
			const data = await websitesAPI.transcribeYouTube(websiteId, url);
			const payload = data as { data?: { file_id?: string; status?: string } };
			const fileId = payload?.data?.file_id;
			if (!fileId) return;
			websitesStore.setTranscriptEntryLocal(websiteId, videoId, {
				status: payload?.data?.status ?? "queued",
				file_id: fileId,
				updated_at: new Date().toISOString()
			});
		} catch (error) {
			toast.error("Transcript failed", { description: "Please try again." });
		}
	}

	async function pollTranscriptJob(
		fileId: string,
		websiteId: string,
		videoId: string
	): Promise<void> {
		if (transcriptPollingFileId === fileId) return;
		stopTranscriptPolling();
		transcriptPollingFileId = fileId;
		transcriptPollingId = setInterval(async () => {
			try {
				const meta = await ingestionAPI.get(fileId);
				const status = meta?.job?.status;
				if (!status) return;
				if (status === "ready") {
					stopTranscriptPolling();
					websitesStore.setTranscriptEntryLocal(websiteId, videoId, {
						status: "ready",
						file_id: fileId,
						updated_at: new Date().toISOString()
					});
					if ($websitesStore.active?.id === websiteId) {
						await websitesStore.loadById(websiteId);
					}
					toast.success("Transcript ready", {
						description: "Transcript appended to the website."
					});
					return;
				}
				if (status === "failed" || status === "canceled") {
					stopTranscriptPolling();
					websitesStore.setTranscriptEntryLocal(websiteId, videoId, {
						status: "failed",
						file_id: fileId,
						updated_at: new Date().toISOString()
					});
					toast.error("Transcript failed", {
						description: "Click to retry transcription.",
						action: {
							label: "Retry",
							onClick: () => retryTranscript(websiteId, videoId)
						}
					});
				}
			} catch (error) {
				stopTranscriptPolling();
			}
		}, 5000);
	}

	$: if (pendingTranscript && pendingTranscript.entry.file_id) {
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
		<div
			class="things-status"
			aria-live="polite"
			title={bridgeSeenAt ? `Last seen ${bridgeSeenAt}` : ""}
		>
			<span class="label">Bridge</span>
			<span
				class="dot"
				class:online={bridgeStatus === "online"}
				class:offline={bridgeStatus === "offline"}
				class:loading={bridgeStatus === "loading"}
			></span>
		</div>
		{#if transcriptStatus}
			<div class="transcript-status" data-status={transcriptStatus}>
				<span class="label">{transcriptLabel}</span>
				<span class="dot"></span>
			</div>
		{/if}
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

	.transcript-status {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		padding: 0.25rem 0.6rem;
		border-radius: 999px;
		border: 1px solid var(--color-border);
		background: var(--color-muted);
		font-size: 0.72rem;
		font-weight: 600;
		color: var(--color-foreground);
	}

	.transcript-status .dot {
		width: 0.45rem;
		height: 0.45rem;
		border-radius: 999px;
		background: var(--color-muted-foreground);
	}

	.transcript-status[data-status="processing"] .dot {
		background: #d99a2b;
	}

	.transcript-status[data-status="ready"] .dot {
		background: #38a169;
	}

	.transcript-status[data-status="failed"] .dot {
		background: #e25555;
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
