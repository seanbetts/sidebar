<script lang="ts">
	import { TooltipProvider } from '$lib/components/ui/tooltip';
	import Sidebar from '$lib/components/left-sidebar/Sidebar.svelte';
</script>

<TooltipProvider delayDuration={0}>
	<Sidebar />
</TooltipProvider>
