<script lang="ts">
	import { TooltipProvider } from '$lib/components/ui/tooltip';

	let { children } = $props();
</script>

<TooltipProvider delayDuration={250}>
	{@render children?.()}
</TooltipProvider>
