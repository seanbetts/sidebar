<script lang="ts">
	import { Plus } from 'lucide-svelte';
	import { websitesStore } from '$lib/stores/websites';
	import SidebarSectionHeader from '$lib/components/left-sidebar/SidebarSectionHeader.svelte';
	import WebsitesPanel from '$lib/components/websites/WebsitesPanel.svelte';
	import { Button } from '$lib/components/ui/button';
	import { onMount } from 'svelte';
	import { Tooltip, TooltipContent, TooltipTrigger } from '$lib/components/ui/tooltip';
	import { TOOLTIP_COPY } from '$lib/constants/tooltips';
	import { canShowTooltips } from '$lib/utils/tooltip';

	export let active = false;
	export let onNewWebsite: () => void;

	let tooltipsEnabled = false;
	onMount(() => {
		tooltipsEnabled = canShowTooltips();
	});
</script>

<div class="panel-section" class:hidden={!active}>
	<SidebarSectionHeader
		title="Websites"
		searchPlaceholder="Search websites..."
		onSearch={(query) => websitesStore.search(query)}
		onClear={() => websitesStore.load(true)}
	>
		<svelte:fragment slot="actions">
			<Tooltip disabled={!tooltipsEnabled}>
				<TooltipTrigger>
					{#snippet child({ props })}
						<Button
							size="icon"
							variant="ghost"
							class="panel-action"
							{...props}
							onclick={(event) => {
								props.onclick?.(event);
								onNewWebsite();
							}}
							aria-label="Save website"
						>
							<Plus size={16} />
						</Button>
					{/snippet}
				</TooltipTrigger>
				<TooltipContent side="right">{TOOLTIP_COPY.saveWebsite}</TooltipContent>
			</Tooltip>
		</svelte:fragment>
	</SidebarSectionHeader>
	<div class="files-content websites-content">
		<WebsitesPanel />
	</div>
</div>

<style>
	.websites-content {
		overflow: hidden;
		flex: 1;
		min-height: 0;
		display: flex;
		flex-direction: column;
		height: 100%;
	}
</style>
