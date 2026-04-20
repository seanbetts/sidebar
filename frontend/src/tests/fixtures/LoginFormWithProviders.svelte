<script lang="ts">
	import LoginForm from '$lib/components/auth/LoginForm.svelte';
	import { TooltipProvider } from '$lib/components/ui/tooltip';
</script>

<TooltipProvider delayDuration={0}>
	<LoginForm />
</TooltipProvider>
