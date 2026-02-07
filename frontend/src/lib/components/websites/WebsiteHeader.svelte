<script lang="ts">
	import {
		Pin,
		PinOff,
		Pencil,
		Copy,
		Type,
		Check,
		Link,
		Download,
		Archive,
		ArchiveRestore,
		Trash2,
		X,
		Menu
	} from 'lucide-svelte';
	import { Button } from '$lib/components/ui/button';
	import * as Popover from '$lib/components/ui/popover/index.js';
	import { Tooltip, TooltipContent, TooltipTrigger } from '$lib/components/ui/tooltip';
	import { TOOLTIP_COPY } from '$lib/constants/tooltips';
	import { onMount } from 'svelte';
	import { canShowTooltips } from '$lib/utils/tooltip';
	import type { WebsiteItem } from '$lib/stores/websites';
	import WebsiteFavicon from '$lib/components/websites/WebsiteFavicon.svelte';
	import {
		formatWebsiteSubtitle,
		getWebsiteDisplayTitle,
		getWebsiteSourceUrl
	} from '$lib/utils/websites';

	export let website: WebsiteItem | null = null;
	export let isCopied = false;
	export let onPinToggle: () => void;
	export let onRename: () => void;
	export let onCopy: () => void;
	export let onCopyTitle: () => void;
	export let onCopyUrl: () => void;
	export let onDownload: () => void;
	export let onArchive: () => void;
	export let onDelete: () => void;
	export let onClose: () => void;

	let tooltipsEnabled = false;
	onMount(() => {
		tooltipsEnabled = canShowTooltips();
	});
</script>

<div class="website-header">
	{#if website}
		<div class="website-meta">
			<div class="title-row">
				<span class="favicon-slot">
					<WebsiteFavicon faviconUrl={website.favicon_url} size={20} />
				</span>
				<div class="title-stack">
					<a
						class="title-text source-title"
						href={getWebsiteSourceUrl(website)}
						target="_blank"
						rel="noopener noreferrer"
					>
						{getWebsiteDisplayTitle(website)}
					</a>
					<span class="subtitle">
						{formatWebsiteSubtitle(website.domain, website.reading_time)}
					</span>
				</div>
			</div>
			<div class="website-meta-row">
				<div class="website-actions">
					<Tooltip disabled={!tooltipsEnabled}>
						<TooltipTrigger>
							{#snippet child({ props })}
								<Button
									size="icon"
									variant="ghost"
									{...props}
									onclick={(event) => {
										props.onclick?.(event);
										onPinToggle();
									}}
									aria-label="Pin website"
								>
									{#if website.pinned}
										<PinOff size={16} />
									{:else}
										<Pin size={16} />
									{/if}
								</Button>
							{/snippet}
						</TooltipTrigger>
						<TooltipContent side="bottom">
							{website.pinned ? TOOLTIP_COPY.pin.on : TOOLTIP_COPY.pin.off}
						</TooltipContent>
					</Tooltip>
					<Tooltip disabled={!tooltipsEnabled}>
						<TooltipTrigger>
							{#snippet child({ props })}
								<Button
									size="icon"
									variant="ghost"
									{...props}
									onclick={(event) => {
										props.onclick?.(event);
										onCopyUrl();
									}}
									aria-label="Copy website URL"
								>
									<Link size={16} />
								</Button>
							{/snippet}
						</TooltipTrigger>
						<TooltipContent side="bottom">Copy URL</TooltipContent>
					</Tooltip>
					<Tooltip disabled={!tooltipsEnabled}>
						<TooltipTrigger>
							{#snippet child({ props })}
								<Button
									size="icon"
									variant="ghost"
									{...props}
									onclick={(event) => {
										props.onclick?.(event);
										onRename();
									}}
									aria-label="Rename website"
								>
									<Pencil size={16} />
								</Button>
							{/snippet}
						</TooltipTrigger>
						<TooltipContent side="bottom">{TOOLTIP_COPY.rename}</TooltipContent>
					</Tooltip>
					<Tooltip disabled={!tooltipsEnabled}>
						<TooltipTrigger>
							{#snippet child({ props })}
								<Button
									size="icon"
									variant="ghost"
									{...props}
									onclick={(event) => {
										props.onclick?.(event);
										onCopy();
									}}
									aria-label={isCopied ? 'Copied website' : 'Copy website'}
								>
									{#if isCopied}
										<Check size={16} />
									{:else}
										<Copy size={16} />
									{/if}
								</Button>
							{/snippet}
						</TooltipTrigger>
						<TooltipContent side="bottom">
							{isCopied ? TOOLTIP_COPY.copy.success : TOOLTIP_COPY.copy.default}
						</TooltipContent>
					</Tooltip>
					<Tooltip disabled={!tooltipsEnabled}>
						<TooltipTrigger>
							{#snippet child({ props })}
								<Button
									size="icon"
									variant="ghost"
									{...props}
									onclick={(event) => {
										props.onclick?.(event);
										onDownload();
									}}
									aria-label="Download website"
								>
									<Download size={16} />
								</Button>
							{/snippet}
						</TooltipTrigger>
						<TooltipContent side="bottom">{TOOLTIP_COPY.downloadMarkdown}</TooltipContent>
					</Tooltip>
					<Tooltip disabled={!tooltipsEnabled}>
						<TooltipTrigger>
							{#snippet child({ props })}
								<Button
									size="icon"
									variant="ghost"
									{...props}
									onclick={(event) => {
										props.onclick?.(event);
										onArchive();
									}}
									aria-label={website.archived ? 'Unarchive website' : 'Archive website'}
								>
									{#if website.archived}
										<ArchiveRestore size={16} />
									{:else}
										<Archive size={16} />
									{/if}
								</Button>
							{/snippet}
						</TooltipTrigger>
						<TooltipContent side="bottom">
							{website.archived ? TOOLTIP_COPY.archive.on : TOOLTIP_COPY.archive.off}
						</TooltipContent>
					</Tooltip>
					<Tooltip disabled={!tooltipsEnabled}>
						<TooltipTrigger>
							{#snippet child({ props })}
								<Button
									size="icon"
									variant="ghost"
									{...props}
									onclick={(event) => {
										props.onclick?.(event);
										onDelete();
									}}
									aria-label="Delete website"
								>
									<Trash2 size={16} />
								</Button>
							{/snippet}
						</TooltipTrigger>
						<TooltipContent side="bottom">{TOOLTIP_COPY.delete}</TooltipContent>
					</Tooltip>
					<Tooltip disabled={!tooltipsEnabled}>
						<TooltipTrigger>
							{#snippet child({ props })}
								<Button
									size="icon"
									variant="ghost"
									{...props}
									onclick={(event) => {
										props.onclick?.(event);
										onClose();
									}}
									aria-label="Close website"
								>
									<X size={16} />
								</Button>
							{/snippet}
						</TooltipTrigger>
						<TooltipContent side="bottom">{TOOLTIP_COPY.close}</TooltipContent>
					</Tooltip>
				</div>
				<div class="website-actions-compact">
					<Popover.Root>
						<Popover.Trigger>
							{#snippet child({ props: popoverProps })}
								<Tooltip disabled={!tooltipsEnabled}>
									<TooltipTrigger>
										{#snippet child({ props: tooltipProps })}
											<Button
												size="icon"
												variant="ghost"
												{...popoverProps}
												{...tooltipProps}
												aria-label="More actions"
											>
												<Menu size={16} />
											</Button>
										{/snippet}
									</TooltipTrigger>
									<TooltipContent side="bottom">More actions</TooltipContent>
								</Tooltip>
							{/snippet}
						</Popover.Trigger>
						<Popover.Content class="website-actions-menu" align="end" sideOffset={8}>
							<button class="website-menu-item" onclick={onPinToggle}>
								{#if website.pinned}
									<PinOff size={16} />
									<span>Unpin</span>
								{:else}
									<Pin size={16} />
									<span>Pin</span>
								{/if}
							</button>
							<button class="website-menu-item" onclick={onRename}>
								<Pencil size={16} />
								<span>Rename</span>
							</button>
							<button class="website-menu-item" onclick={onCopy}>
								{#if isCopied}
									<Check size={16} />
									<span>Copied</span>
								{:else}
									<Copy size={16} />
									<span>Copy</span>
								{/if}
							</button>
							<button class="website-menu-item" onclick={onCopyTitle}>
								<Type size={16} />
								<span>Copy Title</span>
							</button>
							<button class="website-menu-item" onclick={onCopyUrl}>
								<Link size={16} />
								<span>Copy URL</span>
							</button>
							<button class="website-menu-item" onclick={onDownload}>
								<Download size={16} />
								<span>Download</span>
							</button>
							<button class="website-menu-item" onclick={onArchive}>
								{#if website.archived}
									<ArchiveRestore size={16} />
									<span>Unarchive</span>
								{:else}
									<Archive size={16} />
									<span>Archive</span>
								{/if}
							</button>
							<button class="website-menu-item" onclick={onDelete}>
								<Trash2 size={16} />
								<span>Delete</span>
							</button>
							<button class="website-menu-item" onclick={onClose}>
								<X size={16} />
								<span>Close</span>
							</button>
						</Popover.Content>
					</Popover.Root>
				</div>
			</div>
		</div>
	{/if}
</div>

<style>
	.website-header {
		display: flex;
		align-items: center;
		justify-content: flex-start;
		gap: 1rem;
		padding: 0.4rem 1.5rem;
		min-height: 57px;
		border-bottom: 1px solid var(--color-border);
		background-color: var(--color-card);
		container-type: inline-size;
	}

	:global(.dark) .website-header {
		background: linear-gradient(90deg, rgba(0, 0, 0, 0.04), rgba(0, 0, 0, 0));
	}

	.website-meta {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: 1rem;
		width: 100%;
	}

	.title-row {
		display: inline-flex;
		align-items: center;
		gap: 0;
		min-width: 0;
	}

	.favicon-slot {
		display: inline-flex;
		align-items: center;
		padding-left: 0.05rem;
		padding-right: 1rem;
	}

	.title-stack {
		display: inline-flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 0rem;
		min-width: 0;
	}

	.website-meta-row {
		display: inline-flex;
		align-items: center;
		gap: 2rem;
	}

	.subtitle {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		font-size: 0.8rem;
		color: var(--color-muted-foreground);
		min-width: 0;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.website-actions {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
	}

	.website-actions-compact {
		display: none;
	}

	:global(.website-actions-menu) {
		width: max-content !important;
		min-width: 0 !important;
		padding: 0.25rem 0;
	}

	.website-menu-item {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		width: 100%;
		border: none;
		background: none;
		cursor: pointer;
		padding: 0.45rem 0.75rem;
		text-align: left;
		font-size: 0.8rem;
		color: var(--color-popover-foreground);
	}

	.website-menu-item:hover {
		background-color: var(--color-accent);
	}

	.title-text {
		font-size: 1rem;
		font-weight: 600;
		color: var(--color-foreground);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.source-title {
		text-decoration: none;
	}

	.source-title:hover {
		text-decoration: underline;
	}

	.website-meta-row {
		flex-shrink: 0;
	}

	@container (max-width: 700px) {
		.website-actions {
			display: none;
		}

		.website-actions-compact {
			display: inline-flex;
			align-items: center;
		}
	}
</style>
